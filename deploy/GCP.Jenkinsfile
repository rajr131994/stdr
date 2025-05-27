#!/usr/bin/env groovy

def deployToServers(hostnames, folder, sshUser, sshPass, sudoUser, sudoPass, healthUrl) {
   parms = 'RAILS_ENV=$RAILS_ENV RAILS_MASTER_KEY="$RAILS_MASTER_KEY"'
   commands = """#! /bin/bash
if [ -f '/opt/blackline/rails/$folder/tmp/pids/resque.pid' ]
then
   pid=\$(cat /opt/blackline/rails/$folder/tmp/pids/resque.pid)
   echo "Killing running resque instance with PID \$pid"
   kill -QUIT \$pid
   sleep 10
fi
if [ -f '/opt/blackline/rails/$folder/tmp/pids/resque-pool.pid' ]
then
   pid=\$(cat /opt/blackline/rails/$folder/tmp/pids/resque-pool.pid)
   echo "Killing running resque pool instance with PID \$pid"
   kill -QUIT \$pid
   sleep 10
fi
rsync -r --delete --exclude={'env','log','shared','config/puma.rb','.bundle/config','deploy.sh','restart.sh'} /tmp/$folder/ /opt/blackline/rails/$folder/
cd /opt/blackline/rails/$folder
export \$(cat env | grep -v '#' | xargs)
echo "RAILS_ENV:     \$RAILS_ENV"
echo "DATABASE_HOST: \$DATABASE_HOST"
echo "GEM_PATH:      \$GEM_PATH"
echo "Running bundler install --without development test"
$parms bundler install --without development test
echo "Running bundle exec rake app:update:bin"
$parms bundle exec rake app:update:bin
echo "Running bundle exec rails db:create"
$parms bundle exec rails db:create
echo "Running bundle exec rails db:migrate"
$parms bundle exec rails db:migrate
echo "Ensuring log directory exists"
[ -d log ] || mkdir log
echo "Ensuring log/resque-pool.stdout.log file exists"
[ -f log/resque-pool.stdout.log ] || touch log/resque-pool.stdout.log
echo "Ensuring log/resque-pool.stderr.log file exists"
[ -f log/resque-pool.stderr.log ] || touch log/resque-pool.stderr.log
echo "Running bundle exec rake resque:scheduler"
$parms PIDFILE=tmp/pids/resque.pid BACKGROUND=yes bundle exec rake resque:scheduler &
echo "Running bundle exec resque-pool --daemon --environment production"
$parms bundle exec resque-pool --daemon --environment production
exit
"""
   writeFile(file: "./$folder/deploy.sh", text: commands.replace('\r\n', '\n'), encoding: "UTF-8")
   for (String hostname : hostnames) {
      commands = """echo -e '${sudoPass}\\n' | sudo -S systemctl restart sap-puma
echo -e '${sudoPass}\\n' | sudo -S rm -rf /tmp/$folder
sleep 10
result=\$(curl -k ${healthUrl} 2>/dev/null) || true
if [ -n "\$result" -a "\$result" == 'success' ]
then
   echo 'Deployment to server $hostname was successful'
   exit 0
else
   echo 'Deployment to server $hostname was NOT successful'
   exit 1
fi
"""
      writeFile(file: "./$folder/restart.sh", text: commands.replace('\r\n', '\n'), encoding: "UTF-8")
      try {
         println("                    INFO: Pushing source files to target server ${hostname} via SFTP")
         sh """
sshpass -p "${sshPass}" sftp -q -o StrictHostKeyChecking=no ${sshUser.substring(sshUser.indexOf('\\') + 1)}@${hostname} << EOF
cd /tmp
mkdir ${folder}
put -r ./${folder}
quit
EOF
"""
         println("                    INFO: Source files pushed to target server ${hostname} via SFTP")
      } catch (err) {
         println("Caught exception pushing source files to target server ${hostname} via SFTP:")
         println(err.toString())
         currentBuild.result = 'UNSTABLE'
         continue
      }

      try {
      println("                    INFO: Running rails commands on target server ${hostname} via SSH")
      sh """
         sshpass -p "${sshPass}" ssh -q -o StrictHostKeyChecking=no ${sshUser.substring(sshUser.indexOf('\\') + 1)}@${hostname} "chmod +x /tmp/$folder/deploy.sh && chmod +x /tmp/$folder/restart.sh && /bin/bash /tmp/$folder/deploy.sh"
      """
      println("                    INFO: Rails commands run successfully on target server ${hostname} via SSH")
      } catch (err) {
         println("Caught exception running rails commands on target server ${hostname} via SSH:")
         println(err.toString())
         currentBuild.result = 'UNSTABLE'
         continue
      }

      try {
         println("                    INFO: Attempting to restart sap-puma on target server ${hostname} via SSH")
         sh """
            sshpass -p "${sudoPass}" ssh -q -o StrictHostKeyChecking=no ${sudoUser.substring(sudoUser.indexOf('\\') + 1)}@${hostname} "/bin/bash /tmp/$folder/restart.sh"
         """
         println("                    INFO: Restarted sap-puma successfully on target server ${hostname} via SSH")
      } catch (err) {
         println("Caught exception restarting sap-puma on target server ${hostname} via SSH:")
         println(err.toString())
         currentBuild.result = 'UNSTABLE'
      }
   }
}

pipeline {
   agent {
      label 'docker'
   }

   environment {
      SSH_CREDENTIALS_ID = ''
      folderName = 'services.connectors.sap'
      sourceDir = "${env.WORKSPACE}\\${folderName}"
      IMG_REG_PATH = credentials("377180d4-26d6-4320-b772-3e105fcd5899")
      PORT_NUMBER = 3004
      HEALTH_URL = "https://localhost:${PORT_NUMBER}/health_check"
      SUDO_CREDS = credentials('1a45f9fc-2795-4e31-93ab-f341926317eb')
      ServiceName =  'services.connectors.sap'
      ParentService = 'fcs'  // Only supported versions will be accepted.
      def msvCategory = 'services'  // Only supported versions will be accepted.
      SnykScan = true
      SnykVerbose = false
   }

   options {
      timeout(time: 30, unit: 'MINUTES')
      timestamps()
   }

   stages {
      stage('Set build name') {
         steps {
            script {
               print('>>> Validating parameters')
               assert env.Environment && env.Environment != '' : 'ERROR: Environment parameter is required'
               assert !(env.Environment ==~ /(?i)g\d\d[hps]\d\d/) : "ERROR: Invalid value '$env.Environment' provided for Environment parameter. Higher environments must be deployed to using the Deploy_SAP_Connector_GCP_DE Jenkins job."
               assert env.TargetBranch && env.TargetBranch != '' : 'ERROR: TargetBranch parameter is required'
               assert env.TargetBranch in [ 'dev', 'test' ] : "ERROR: Invalid value '$env.TargetBranch' provided for TargetBranch parameter"
               assert env.EmailList && env.EmailList != '' : 'ERROR: EmailList parameter is required'
               print('<<< Validated parameters')
               // e.g.: #1_dev-->US
               currentBuild.displayName = (env.CommitHash == null || env.CommitHash == '') ? currentBuild.displayName + "_${env.TargetBranch}-->${env.Environment}" : currentBuild.displayName + "_${env.CommitHash}-->${env.Environment}"
            }
         }
      }

      stage('Validate environment hostnames') {
         environment {
            def CONFIG_API_URL = credentials('2f71c58e-908d-4aeb-ab96-0196d474f781')
            def AUTH_KEY = credentials('c53a980a-ce9d-4d2a-bb40-5f5decbdd463')
         }
         agent {
            docker {
               image "${env.IMG_REG_PATH}/bl-build-jq:19.0.0"
            }
         }
         steps {
            script {
               println(">>> Validating hostnames for target environment ${env.Environment}")
               HOSTNAME_LIST = sh(returnStdout:true, script: """
                  curl -s -X GET \"${env.CONFIG_API_URL}/infra/configs/connectors/cbe_hostnames\" -H \"accept: application/json\" -H \"API-KEY: ${env.AUTH_KEY}\"  | jq -r -j '.hostnames.${env.Environment.toLowerCase()}'
               """).trim()

               assert HOSTNAME_LIST != null && HOSTNAME_LIST != '' && HOSTNAME_LIST != 'null' : "ERROR: Unable to retrieve hostnames for target environment ${env.Environment}"
               println(">>>>>> Target hostnames: ${HOSTNAME_LIST}")
               println("<<< Hostnames for target environment ${env.Environment} validated")
            }
         }
      }

      stage('Get SSH credentials') {
         steps {
            script {
               def envTypeArray = env.EnvironmentType.split('-')
               envTypeCode = envTypeArray[0].trim()
               envType = envTypeArray[1].trim()
               println(">>> Getting SSH credentials for $envType environment ${env.Environment}")
               switch(envTypeCode) {
                  case 'D':
                     SSH_CREDENTIALS_ID = '122ac5aa-564e-4906-9fc4-873079eb1971'
                     break

                  case 'T':
                     SSH_CREDENTIALS_ID = 'beaa119c-bf93-44d0-913b-da86a1d84221'
                     break

                  default:
                     SSH_CREDENTIALS_ID = null
                     break
               }

               assert SSH_CREDENTIALS_ID != null : "ERROR: Unable to retrieve SSH credentials for $envType environment ${env.Environment}"
               println("<<< Retrieved SSH credentials for $envType environment ${env.Environment}")
            }
         }
      }

      stage('Pull') {
         agent {
            docker {
               image "${env.IMG_REG_PATH}/bl-build-git:2020.02.11"
               reuseNode true
            }
         }
         environment {
            def STASH_CRED = credentials("218a60ea-58d4-40bc-a7f1-30a6578bf4da")
            gitUrl = "https://${STASH_CRED}@stash.blackline.corp/scm/link/services.connectors.s4hana_public_cloud"
         }
         steps {
            script {
               println(">>> Pull stage starting")
               if (fileExists("${env.WORKSPACE}/${folderName}")) {
                  sh """rm -rf ${env.WORKSPACE}/${folderName}"""
               }

               branch = (env.CommitHash != null && env.CommitHash != '') ? "master" : "${env.TargetBranch}"
               println(">>>>>> Cloning branch ${branch} of ${gitUrl} into folder ${folderName}")
               sh """git clone -b ${branch} ${gitUrl} ${folderName}"""

               assert fileExists("${env.WORKSPACE}/${folderName}") : "ERROR: Unable to clone ${folderName} repository"
               if (env.CommitHash != null && env.CommitHash != '') {
                  dir("${env.folderName}") {
                     sh """git checkout ${env.CommitHash}"""
                  }
               }

               println("<<< Pull stage ending")
            }
         }
      }

      stage('Snyk Security Scan') { 
         environment {
            def BUILD_JOB_NAME = 'Build_Service_Handler_Connectors'
         }
         steps {
            println("          >>>>>>>>>> Triggering Downstream Build")

            build job: env.BUILD_JOB_NAME,
               parameters: [
                  string(name: 'ServiceName', value: env.ServiceName),
                  string(name: 'ParentService', value: env.ParentService),
                  booleanParam(name: 'RunScan', value: env.SnykScan),
                  booleanParam(name: 'ScanVerbose', value: env.SnykVerbose)
               ]
         }
      }

      stage('Deploy') {
         agent {
            docker {
               image "${env.IMG_REG_PATH}/bl-build-ssh:20.04.24.00"
               args '-u root:root'
               reuseNode true
            }
         }
         environment {
            def SSH_CREDS = credentials("${SSH_CREDENTIALS_ID}")
         }
         steps {
            script {
               println(">>> Deployment starting")

               println(">>>>>> Deleting deploy folder since it is used for deployment")
               sh "rm -rf ${folderName}/deploy"

               println(">>>>>> Deleting .git folder since it is used for source code management")
               sh "rm -rf ${folderName}/.git"

               hostnames = HOSTNAME_LIST.split(',')
               deployToServers(hostnames, folderName, SSH_CREDS_USR, SSH_CREDS_PSW, SUDO_CREDS_USR, SUDO_CREDS_PSW, HEALTH_URL)
               println("<<< Deployment complete")
            }
         }
      }
   }

   post {
      always {
         println(">>> Initiating Post-Run Cleanup")
         cleanWs()
      }

      success {
         println(">>> Sending email for successful run")
         mail to: "${env.EmailList}",
            subject: "SUCCESS : BlackLine Link SAP Connector Deployment",
            body: "Please review log at ${env.BUILD_URL}consoleFull"
      }

      failure {
         println(">>> Sending email for failed run")
         mail to: "${env.EmailList}",
            subject: "FAILED : BlackLine Link SAP Connector Deployment",
            body: "Please review log at ${env.BUILD_URL}consoleFull"
      }
   }
}

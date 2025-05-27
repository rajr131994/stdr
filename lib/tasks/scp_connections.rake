require 'rails/all'
require 'json'

namespace :scp do
  desc "SCP connection"

#  task :connections, [:json, :node, :region_code, :environment_type ]  => :environment do |task, args|
  task :connections  => :environment do

    logger = Rails.logger
    #Read SCP json
    #Destination client id
    #Destination client secret
    #Xsuaa client id
    #Xsuaa client secret

    logger_service = AppServices::LoggerService.new({ log_params: {
        logger: logger }})

    ARGV.each { |a| task a.to_sym do ; end }

    identity_zone = ARGV[1]
    node = ARGV[2]
    region_code = ARGV[3]
    environment_type = ARGV[4]
    cloud_provider_region_code = ARGV[5]
    host_extractor = ARGV[6]

    token_host = ARGV[7]
    client_id_destination = ARGV[8].gsub("\\!","!")
    client_secret_dest = ARGV[9].gsub("\\$","$")
    client_id_extractor = ARGV[10].gsub("\\!","!")
    client_secret_extract = ARGV[11].gsub("\\$","$")
    host_destination = ARGV[12]

    logger_service.log_message('info', "Ruby SCP connections",
                                "identity_zone : #{identity_zone}")
    logger_service.log_message('info', "Ruby SCP connections",
                                "node : #{node}")
    logger_service.log_message('info', "Ruby SCP connections",
                                "region_code: #{region_code}")
    logger_service.log_message('info', "Ruby SCP connections",
                                "environment_type : #{environment_type}")
    logger_service.log_message('info', "Ruby SCP connections",
                                "cloud_provider_region_code: #{cloud_provider_region_code}")
    logger_service.log_message('info', "Ruby SCP connections",
                                "host_extractor : #{host_extractor}")
    logger_service.log_message('info', "Ruby SCP connections",
                                "token_host: #{token_host}")
    logger_service.log_message('info', "Ruby SCP connections",
                                "client_id_destination : #{client_id_destination}")
    logger_service.log_message('info', "Ruby SCP connections",
                                "host_destination : #{host_destination}")

    if not ARGV[1].nil? and not ARGV[2].nil? and not ARGV[3].nil? and not ARGV[4].nil? and not ARGV[5].nil? and not ARGV[6].nil? and not ARGV[7].nil? and not ARGV[8].nil? and not ARGV[9].nil? and not ARGV[10].nil? and not ARGV[11].nil? and not ARGV[12].nil?

      #json_connection_profile = JSON.parse(ARGV[1])

      #identity_zone = json_connection_profile["VCAP_SERVICES"]["destination"][0]["credentials"]["identityzone"]
      #token_host = json_connection_profile["VCAP_SERVICES"]["xsuaa"][0]["credentials"]["uaadomain"]

      if not identity_zone.include? region_code.downcase
        # logger.error("VCAP services from SCP doesn't match region code: #{region_code} node: #{node}")
        logger_service.log_message('error', "Ruby SCP connections",
                                    "VCAP services from SCP doesn't match region code: #{region_code} node: #{node}")
        break
      end

      if not identity_zone.include? environment_type.downcase
        #logger.error("VCAP services from SCP doesn't match node: #{node} environment: #{environment_type}")
        logger_service.log_message('error', "Ruby SCP connections",
                                    "VCAP services from SCP doesn't match node: #{node} environment: #{environment_type}")
        break
      end

      if not token_host.include? cloud_provider_region_code.downcase
        #logger.error("VCAP services from SCP doesn't match node: #{node} cloud_provider_region_code: #{cloud_provider_region_code}")
        logger_service.log_message('error', "Ruby SCP connections",
                                    "VCAP services from SCP doesn't match node: #{node} cloud_provider_region_code: #{cloud_provider_region_code}")
        break
      end

      #Parse and determine variables from VCAP SERVICES JSON
      #client_id_destination = json_connection_profile["VCAP_SERVICES"]["destination"][0]["credentials"]["clientid"]
      #client_secret_dest = json_connection_profile["VCAP_SERVICES"]["destination"][0]["credentials"]["clientsecret"]

      #client_id_extractor = json_connection_profile["VCAP_SERVICES"]["xsuaa"][0]["credentials"]["clientid"]
      #client_secret_extract = json_connection_profile["VCAP_SERVICES"]["xsuaa"][0]["credentials"]["clientsecret"]

      #host_destination = json_connection_profile["VCAP_SERVICES"]["destination"][0]["credentials"]["uri"]

      # replace_host = "//"+ environment_type.downcase + "-s4hextractor-"+ node+".cfapps"
      # host_extractor = token_host
      # host_extractor["authentication"] = replace_host
      #
      # array_domain = token_host.split(".")
      # cloud_provider_region_code = array_domain[1]

      #Find correspondong scp Connection record
      # Unique key : node, region_code and environment_type
      scp_connection = ScpConnection.find_by(:node => node, :region_code => region_code, :environment_type => environment_type)

      if not scp_connection.nil?

        scp_connection.update_attribute(:client_id_extractor, client_id_extractor)
        scp_connection.update_attribute(:client_id_destination, client_id_destination)

        scp_connection.update_attribute(:client_secret_extract, client_secret_extract)
        scp_connection.update_attribute(:client_secret_dest, client_secret_dest)

        scp_connection.update_attribute(:token_host, token_host)
        scp_connection.update_attribute(:token_endpoint, "/oauth/token")

        scp_connection.update_attribute(:host_destination, host_destination)
        scp_connection.update_attribute(:host_endpoint_destination, "/destination-configuration/v1/subaccountDestinations")
        scp_connection.update_attribute(:host_extractor, host_extractor)

        scp_connection.update_attribute(:host_endpoint_extractor, "/api/rest/v1")
        scp_connection.update_attribute(:host_endpoint_extract_asn, "/api/asynch/v1")

        scp_connection.update_attribute(:active, true)
        scp_connection.update_attribute(:cloud_provider_region_code, cloud_provider_region_code)

      else
        # Create new scp connection record if corresponding record not exist
        ScpConnection.create!({
                                  node: node,
                                  token_host: token_host,
                                  token_endpoint: "/oauth/token",

                                  client_id_extractor: client_id_extractor,
                                  client_id_destination: client_id_destination,
                                  client_secret_extract: client_secret_extract,
                                  client_secret_dest: client_secret_dest,

                                  host_destination: host_destination,
                                  host_endpoint_destination: "/destination-configuration/v1/subaccountDestinations",

                                  host_extractor: host_extractor,
                                  host_endpoint_extractor: "/api/rest/v1",
                                  host_endpoint_extract_asn: "/api/asynch/v1",

                                  region_code: region_code,
                                  environment_type: environment_type,
                                  active: true,
                                  cloud_provider_region_code: cloud_provider_region_code
                              })

      end
    else
      logger.error("Not all arguments are present")
    end


  end

end
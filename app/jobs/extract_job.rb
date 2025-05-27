class ExtractJob

  @queue = :extract

  attr_accessor :logger

  def self.perform(tenant, scheduleid, runname, program, hostname, blackline_instance_id)


    @status_error = 7
    @status_ok = 4
    @status_planned = 1
    @status_running = 3

    #Default values
    @block_size = 50000
    @max_blocks = 1000
    @time_out = 3600
    @pool_size = 0
    @error = false
    @error_message = []

    # Set logger
    logger = Rails.logger

    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})

    @logger_service.log_message('info', "ExtractJob",
                                "Extract Job - Apartment id: #{tenant} Start Extract:  #{Time.now} Integration Id:  #{scheduleid}")

    Apartment::Tenant.switch!(tenant)

    extractdata = ExtractData.new()

    # Job instance
    extractjob = ExtractJob.new()

    # Check if redis is active
    correct = extractjob.check_redis_server(@logger_service)

    if correct

      #Get schedule id
      schedule_instance = extractjob.get_schedule_instance(scheduleid, tenant, @logger_service)

      #Get template id from database and create temporary template for SCC component
      #A temporary template instance is needed because the system don't want to store a temporary template in the database
      template_db = extractjob.get_template_db(schedule_instance, tenant, @logger_service)
      template = extractjob.get_new_template(template_db,schedule_instance)

      if !schedule_instance.file_name.nil? and schedule_instance.file_name != ""
        template.file_name_prefix = schedule_instance.file_name
      end

      #Get defintion id and deftype id
      definition = extractjob.get_definition(template_db, tenant, @logger_service)

      #Get deftype
      deftype = extractjob.get_def_type(definition, tenant, @logger_service)

      #Get connection_profile
      connection_profile = extractjob.get_connection_profile(schedule_instance, tenant, @logger_service)

      #Get destinations
      erp_destination_db = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => extractdata.erp_destination_type)

      #Get FTP destination
      file_destination_db = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => extractdata.ftp_destination_type)
      # file_destination_db = extractjob.check_and_get_destination(file_destination_db, @logger_service, template_db, extractdata, connection_profile, tenant)
      if file_destination_db.nil?
        logger.log_message('error', "ExtractJob", "Extract Job - Apartment id: #{tenant} No FTP destination present, Error on connection profile : #{connection_profile.id}")
        @error = true
        @error_message = 'FTP destination is not present in the selected connection profile'
      end

      # Client for API Ingestion
      restextractor = connection_profile.gke_enabled  ? ExtractorService.new(@logger_service, tenant)
                                                      : RestscpData.new(@logger_service, tenant)


      integration_service = AppServices::IntegrationService.new({integration_params: {
          type: nil, logger: logger, extract_data: extractdata, rest_extractor: restextractor}})

      extractor_description_temp = [ "" ]
      extractor_description = (extractor_description_temp << integration_service.get_def_descr_array).flatten!

      if definition.definition_description.nil? || definition.definition_description.empty?

        logger.log_message('error', "ExtractJob",
                           "Extract Job - Apartment Id: #{tenant} The definition description is not present or empty #{runname}")
      else
        type = (extractor_description.find_index(definition.definition_description).to_i)

        if type == 0
          @error = true
          logger.log_message('error', "ExtractJob",
                             "Extract Job - Apartment Id: #{tenant} The definition description is invalid : #{definition.definition_description} for #{runname}")

          @error = integration_service.get_error
          if integration_service.get_error_message && integration_service.get_error_message.is_a?(Array)
            integration_service.get_error_message.each {|x| @errormessage << x.html_safe}
          elsif integration_service.get_error_message && integration_service.get_error_message.is_a?(String)
            @errormessage << integration_service.get_error_message.html_safe
          end
        else

          integration_service.set_type(type)
          integration_service.set_logger(logger)

          begin

            template_lines_array = integration_service.get_template_lines(logger, schedule_instance, definition, scheduleid, template_db, connection_profile, blackline_instance_id, erp_destination_db, template, type)
          rescue => ex

            @error = true
            @error_message << ex.message
          end

        end
      end

      # check if the extract job is scheduled by a run once action
      extract_instance_db = ExtractRun.find_by(run_name: runname, manual: true)

      if extract_instance_db.nil?
        # if the extract job is a regular interval action
        extract_instance_db = extractjob.get_extract_instance_db(runname, program, schedule_instance, template_db,
                                                                 erp_destination_db, file_destination_db, nil,
                                                                 definition, deftype)
      end


      if @error == true

        extractjob.update_status_extract_run(@status_error,extract_instance_db)

        extractjob.update_functional_log(@error_message,extract_instance_db)

      end


      if (not schedule_instance.nil? || erp_destination_db.nil? || file_destination_db.nil?) and @error == false
        template.template_lines = template_lines_array

        if file_destination_db.pgp_encryption
          template.file_name_extension = "pgp"
        end

        extract_instance_json = extractjob.get_extract_instance_json(runname, program, schedule_instance, template,
                                                                     erp_destination_db, file_destination_db, nil,
                                                                     definition, deftype)

        extractjson = extractjob.get_extract_json(extract_instance_json, extract_instance_db, blackline_instance_id)
        # Warning: DO NOT remove the below delete statement, it will corrupt the data
        extract_instance_json.delete

      else
        @error = true
        @logger_service.log_message('error', "ExtractJob",
                                    "Extract Job - Apartment id: #{tenant} Error with integration #{runname}, No schedule, S4H destination or FTP/IAP destination found")
      end

      # Start processing JOB
      if not extractjson.nil? and
          not extract_instance_json.nil? and
          not extract_instance_db.nil? and @error == false

        @logger_service.log_message('info', "ExtractJob",
                                    "Extract Job - Apartment id: #{tenant} Found extract json and destinations for Schedule ID : #{scheduleid}")

        #update job status
        extractjob.update_job_status(schedule_instance, extract_instance_db, scheduleid, @logger_service, tenant,@status_running)

        # When the exractor runs on the local machine use blackline instance id 22905
        blackline_instance_id = extractjob.get_dev_blackline_instance_id(blackline_instance_id)

        #If Account analysis extractor get extra template
        if definition.definition_description == "Account Analysis extract S4H"

          template_acc_analysis = Template.find_by(:definition_id => definition.id, :template_description => "GetAccountTransactionAnalysis")
          if template_acc_analysis.nil?
            @logger_service.log_message('error', "ExtractRuns",
                                        "Error with configuration - Template not found with definition id: #{definition.id}")
            raise ActiveRecord::RecordNotFound, "Error with configuration - Template not found with definition id: #{definition.id}"
          else
            template_acc_analysis.file_name_extension = schedule_instance.file_extension_acc

          end

          template_acc_instance = Template.new({
                                                   definition_id: template_acc_analysis.definition_id,
                                                   template_description: template_acc_analysis.template_description,
                                                   file_name_prefix: !schedule_instance.txn_file_name.nil? && schedule_instance.txn_file_name != "" ? schedule_instance.txn_file_name : template_acc_analysis.file_name_prefix,
                                                   file_name_extension: file_destination_db.pgp_encryption ? template.file_name_extension = "pgp" : schedule_instance.file_extension_acc,
                                                   include_timestamp: template_acc_analysis.include_timestamp,
                                                   test_run: template_acc_analysis.test_run,
                                                   number_format: template_acc_analysis.number_format,
                                                   date_format: template_acc_analysis.date_format,
                                                   csv_format: template_acc_analysis.csv_format,
                                                   delimiter: template_acc_analysis.delimiter,
                                                   line_break: template_acc_analysis.line_break,
                                                   csv_quote: template_acc_analysis.csv_quote,
                                                   include_header_line: template_acc_analysis.include_header_line,
                                                   language_key: template_acc_analysis.language_key
                                               })

        end

        if not template_acc_analysis.nil?

          begin

            array_template_lines_acc_analysis = integration_service.get_template_lines(logger, schedule_instance, definition, scheduleid, template_acc_analysis, connection_profile, blackline_instance_id, erp_destination_db, template_acc_instance, type)

          rescue ActiveRecord::Rollback => ex

            @error = true
            @error_message << ex.message
          end

          if @error == true

            extractjob.update_status_extract_run(@status_error,extract_instance_db)

            extractjob.update_functional_log(@error_message,extract_instance_db)

            return nil
          end

          template_acc_instance.template_lines = array_template_lines_acc_analysis

        end

        extract_json_call = extractjob.get_full_extract_json_call(extractjson, blackline_instance_id, tenant,
                                                                  extract_instance_db.id, logger, extract_instance_db,template_acc_instance,extractjob)

        if extractjob.get_error == false
          extract_response = restextractor.sapquery_async(@time_out, extract_json_call)

          if not extract_response.nil? and extract_response.code == 200
            
            @logger_service.log_message('info', "ExtractJob",
                               "Extract Job - Apartment id #{tenant} Response...OK >> #{Time.now} Status code: #{extract_response.code}")

            extractjob.schedule_status_job(extractdata.status_wait, extract_instance_db.id, runname)

          else

            status_code = ""
            if not extract_response.nil?
              @error = restextractor.get_error
              @error_message = restextractor.get_error_message

              extractjob.response_handling(extract_response, runname, @logger_service, schedule_instance,
                                           erp_destination_db, extract_instance_db, extractdata.scp_wait,
                                           extractjson, restextractor, extractjob, @time_out,
                                           connection_profile, blackline_instance_id, tenant, @error_message)
              status_code = extract_response.code
            end

            @logger_service.log_message('error', "ExtractJob",
                                        "Extract Job - Apartment id: #{tenant} Error HTTP timeout with SCP extract service for Run ID : #{extract_instance_db.id}")

            #Stop schedule job
            extractjob.cancel_extract_job(runname)
            @logger_service.log_message('info', "ExtractJob",
                                        "Extract Job - Apartment id: #{tenant} Integration will be stopped in resque runname : #{runname}")

            extract_instance_db.update_attribute(:status, @status_error)
            extract_instance_db.update_attribute(:job_log_message, "{\"message\": [{ \"name\": \"Extractor job error\", \"text\": \"Extract Job - No Response - Integration will be stopped in resque runname : #{runname} http_status: #{status_code}\"}]}")

          end


          @logger_service.log_message('debug', "ExtractJob",
                                      "Extract Job ..finished tenant: #{tenant} runid: #{extract_instance_db.id} >> #{Time.now} Status: #{extract_instance_db.status}")

        end
      else

        extract_instance_db.update_attribute(:status, @status_error)
        if @error_message.empty?
          @logger_service.log_message('error', "ExtractJob",
                                      "Extract Job - Apartment id #{tenant} Error with payload json for SCP service and/or IAPI/FTP destination not found")
          extract_instance_db.update_attribute(:job_log_message, "{\"message\": [{ \"name\": \"Extractor job error\", \"text\": \"Extract Job - Error with payload json for SCP service and/or IAPI/FTP destination not found\"}]}")
        else
          #error_message = @error_message[0].join(', ')
          error_message = @error_message

          extract_instance_db.update_attribute(:job_log_message, "{\"message\": [{ \"name\": \"Extractor job error\", \"text\": \"#{error_message[0]}\"}]}")
          @logger_service.log_message('error', "ExtractJob",
                                      "Extract Job - Apartment id #{tenant} #{error_message[0]}")
        end

      end
    end
  end



  def response_handling(extract_response, runname, logger, schedule_instance, scp_destination_db,
                        extract_instance_db, scp_wait, extractjson, restextractor, extractjob, time_out,
                        connection_profile, blackline_instance_id, tenant, error_message)

    #Check error handling
    case extract_response.code



    when 404


      job_log_message = ""
      if not error_message.nil?
        error_message.each do |message|
          job_log_message += message
        end

      end

      if not extract_response.parsed_response["job_log_message"].nil?
        job_log_message += extract_response.parsed_response["job_log_message"]
      end

      extract_instance_db.update_attribute(:status, 7)
      extract_instance_db.update_attribute(:job_log_message, "{\"message\": [{ \"name\": \"Extractor job error\", \"text\": \"#{job_log_message}\"}]}")
    when 408 || 503
      #unavailable

      #Retry
      logger.log_message('info', "ExtractJob",
                         "Extract Job - Apartment id #{tenant} SCP service unavailable...RETRY >> #{Time.now} Status code: #{extract_response.code}")
      count = 0
      while count < schedule_instance.max_number_of_runs.to_i || extract_response != 200
        sleep(scp_wait.to_i)
        extract_response = restextractor.sapquery_async(time_out, extractjson)

        count = count + 1
      end

      if not (extract_response == 200 || extract_response == 201 || extract_response == 203)
        extractjob.cancel_extract_job(runname)

        logger.log_message('error', "ExtractJob",
                           "Extract Job - Apartment id #{tenant} SCP service unavailable...RETRY NOT OK >> #{Time.now} Status code: #{extract_response.code}")

        extract_instance_db.update_attribute(:status, 7)
        extract_instance_db.update_attribute(:job_log_message, "{\"message\": [{ \"name\": \"Extractor job error\", \"text\": \"Extract Job - SCP service unavailable...RETRY NOT OK >> #{Time.now} Status code: #{extract_response.code}\"}]}")
      else
        #All ok

        logger.log_message('info', "ExtractJob",
                           "Extract Job - Apartment id #{tenant} SCP service available...RETRY OK >> #{Time.now} Status code: #{extract_response.code}")
        parsed_response = extract_response.parsed_response
      end

    when 500...600
      #other error
      extractjob.cancel_extract_job(runname)

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Apartment id #{tenant} SCP service available...ERROR >> #{Time.now} Status code: #{extract_response.code}")

      extract_instance_db.update_attribute(:status, 7)
      extract_instance_db.update_attribute(:job_log_message, "{\"message\": [{ \"name\": \"Extractor job error\", \"text\": \"Extract Job - SCP http error status code #{extract_response.code}\"}]}")
    else
      extractjob.cancel_extract_job(runname)

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Apartment id #{tenant} SCP service available...ERROR >> #{Time.now} Status code: #{extract_response.code}")

      extract_instance_db.update_attribute(:status, 7)
      extract_instance_db.update_attribute(:job_log_message, "{\"message\": [{ \"name\": \"Extractor job error\", \"text\": \"Extract Job - SCP service available...ERROR >> #{Time.now} Status code: #{extract_response.code}\"}]}")
    end

    return parsed_response
  end

  def get_full_extract_json_call(extractjson, blackline_instance_id, tenant, run_id, logger,
                                 extract_instance_db,template_acc_instance,extract_job)

    logger = Rails.logger

    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})

    parsed_json = JSON(extractjson)
    parsed_json["blackline_instance_id"] = blackline_instance_id
    #appartment tenant id
    parsed_json["tenant"] = tenant

    #Add extra template + template lines
    if not template_acc_instance.nil?
      parsed_json["template_acc"] = template_acc_instance

    end

    errors = []
    text_host = "on S4H connector server #{  ENV['BL_ENV_NAME'] }"
    if ENV["STS_S4H_API_HOST"].nil? || ENV["STS_S4H_API_HOST"].empty?
      @logger_service.log_message('error', "ExtractJob",
                                  "Extract Job - environment variable STS_S4H_API_HOST not present or empty #{text_host}")
      errors << "Extract Job - environment variable STS_S4H_API_HOST not present or empty #{text_host}"
    end
    if ENV["STS_TOKEN_HOST"].nil? || ENV["STS_TOKEN_HOST"].empty?
      @logger_service.log_message('error', "ExtractJob",
                                  "Extract Job - environment variable STS_TOKEN_HOST not present or empty #{text_host}")
      errors << "Extract Job - environment variable STS_TOKEN_HOST not present or empty #{text_host}"
    end
    if ENV["STS_TOKEN_ENDPOINT"].nil? || ENV["STS_TOKEN_ENDPOINT"].empty?
      @logger_service.log_message('error', "ExtractJob",
                                  "Extract Job - environment variable STS_TOKEN_ENDPOINT not present or empty #{text_host}")
      errors << "Extract Job - environment variable STS_TOKEN_ENDPOINT not present or empty #{text_host}"
    end
    if ENV["STS_SCOPE_NAME"].nil? || ENV["STS_SCOPE_NAME"].empty?
      @logger_service.log_message('error', "ExtractJob",
                                  "Extract Job - environment variable STS_SCOPE_NAME not present or empty #{text_host}")
      errors << "Extract Job - environment variable STS_SCOPE_NAME not present or empty #{text_host}"
    end
    if ENV["STS_CLIENT_ID"].nil? || ENV["STS_CLIENT_ID"].empty?
      @logger_service.log_message('error', "ExtractJob",
                                  "Extract Job - environment variable STS_CLIENT_ID not present or empty #{text_host}")
      errors << "Extract Job - environment variable STS_CLIENT_ID not present or empty #{text_host}"
    end
    if ENV["STS_CLIENT_SECRET"].nil? || ENV["STS_CLIENT_SECRET"].empty?
      @logger_service.log_message('error', "ExtractJob",
                                  "Extract Job - environment variable STS_CLIENT_SECRET not present #{text_host}")
      errors << "Extract Job - environment variable STS_CLIENT_SECRET not present or empty #{text_host}"
    end

    if not errors.empty?
      @error = true

      extract_instance_db.update_attribute(:status, 7)

      job_log_message = get_error_job_log_array(errors)

      extract_instance_db.update_attribute(:job_log_message, job_log_message)
    else
      @error = false

      extract_job.set_api_ruby_credentials(run_id,parsed_json)
    end
    return parsed_json.to_json(:methods => :template_lines)

  end


  def set_api_ruby_credentials(run_id,parsed_json)

    parsed_json["api_username"] = ENV["STS_CLIENT_ID"]
    parsed_json["api_password"] = ENV["STS_CLIENT_SECRET"]

    parsed_json["api_host"] = ENV["STS_S4H_API_HOST"]
    parsed_json["api_token_host"] = ENV["STS_TOKEN_HOST"]
    parsed_json["api_token_endpoint"] = ENV["STS_TOKEN_ENDPOINT"]
    parsed_json["api_scope"] = ENV["STS_SCOPE_NAME"]

    parsed_json["id"] = run_id

    return parsed_json

  end


  def get_error_job_log_array(errors)

    job_log_message = "{\"message\": ["
    i = 1
    errors.each do |error|

      if i > 1
        job_log_message += ","
      end

      job_log_message += "{ \"name\": \"Extractor job error\", \"text\": \"#{error}\"}"

      i += 1
    end
    job_log_message += "]}"

    return job_log_message

  end


  def get_extract_instance_json(runname, program, schedule_instance, template, erp_destination_db, file_destination_db,
                                gist_destination_db, definition, deftype)

    extract_instance = ExtractRun.new({
                                          schedule: schedule_instance,
                                          template: template,
                                          erp_destination: erp_destination_db,
                                          file_destination: file_destination_db,
                                          definition: definition,
                                          deftype: deftype,
                                          run_name: runname,
                                          execution_program: program,
                                          status: 1,
                                          scheduled_by: 'Resque',
                                          scheduled_on: Time.now,
                                          scheduled_start: Time.now + 1.minutes,
                                          latest_start_time: Time.now + 1.hours,
                                          no_user: true,
                                          generated: true,
                                          manual: false,
                                          test_run: false
                                      })

    return extract_instance
  end

  def get_extract_instance_db(runname, program, schedule_instance, template, erp_destination_db, file_destination_db,
                              gist_destination_db, definition, deftype)

    extract_instance = ExtractRun.create!({
                                              schedule: schedule_instance,
                                              template: template,
                                              erp_destination: erp_destination_db,
                                              file_destination: file_destination_db,
                                              definition: definition,
                                              deftype: deftype,
                                              run_name: runname,
                                              execution_program: program,
                                              status: 1,
                                              scheduled_by: 'Resque',
                                              scheduled_on: Time.now,
                                              scheduled_start: Time.now + 1.minutes,
                                              latest_start_time: Time.now + 1.hours,
                                              no_user: true,
                                              generated: true,
                                              manual: false,
                                              test_run: false
                                          })
    updated_runname = runname + "_" + extract_instance.id.to_s

    extract_instance.update_attribute(:run_name, updated_runname)

    return extract_instance
  end

  def get_schedule_instance(schedule_id, tenant, logger)

    #Get schedule id
    schedule_instance = Schedule.find(schedule_id)
    if schedule_instance.nil?
      #logger.error "Extract Job - No schedule found, schedule : #{schedule_id}"
      logger.log_message('error', "ExtractJob",
                         "Extract Job - Apartment id  : #{tenant} No schedule found, schedule : #{schedule_id}")
    else
      #logger.info "Extract Job - schedule found, schedule : #{schedule_id}"
      logger.log_message('info', "ExtractJob",
                         "Extract Job - Schedule found, schedule : #{schedule_id}")
    end

    return schedule_instance
  end

  def get_template_db(schedule_instance, tenant, logger)

    #Get template id
    template_db = Template.find_by(:id => schedule_instance.template_id)
    if template_db.nil?

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Apartment id : #{tenant} No template found, schedule : #{schedule_instance.template_id}")
    else

      logger.log_message('info', "ExtractJob",
                         "Extract Job - Template found, schedule : #{schedule_instance.template_id}")
    end

    return template_db

  end

  def get_definition(template, tenant, logger)

    #Get defintion id and deftype id
    definition = Definition.find(template.definition_id)
    if definition.nil?

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Apartment id  : #{tenant} No definition found, schedule : #{template.definition_id}")
    else

      logger.log_message('info', "ExtractJob",
                         "Extract Job - Definition found, schedule : #{template.definition_id}")
    end

    return definition
  end

  def get_def_type(definition, tenant, logger)

    #Get deftype
    deftype = Deftype.find(definition.deftype_id)
    if deftype.nil?

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Apartment id : #{tenant} No definition type found, schedule : #{definition.deftype_id}")
    else

      logger.log_message('info', "ExtractJob",
                         "Extract Job - Definition type found, schedule : #{definition.deftype_id}")
    end

    return deftype

  end

  def get_connection_profile(schedule_instance, tenant, logger)

    #Get connection_profile
    connection_profile = ConnectionProfile.find_by_id(schedule_instance.connection_profile_id)
    if connection_profile.nil?

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Apartment id : #{tenant} No connection profile found, id : #{schedule_instance.connection_profile_id}")
    else

      logger.log_message('info', "ExtractJob",
                         "Extract Job - Connection profile found, id : #{schedule_instance.connection_profile_id}")
    end

    return connection_profile

  end

  def get_extract_json(extract_instance, extract_instance_db, blackline_instance_id)

    #Change CDS service name according to execution_program
    if extract_instance.execution_program == 'ConsolidatedBalanceSheetAccountsV4'
      extract_instance.erp_destination.cds_service_name= 'YY1_BLC_C005'
    elsif  extract_instance.execution_program == 'FinancialStatementHierarchyV4'
      extract_instance.erp_destination.cds_service_name= 'YY1_BLC_C002'
    elsif  extract_instance.execution_program == 'ConsolidationAccountSettingsV4'
      extract_instance.erp_destination.cds_service_name= 'YY1_BLC_C004'
    elsif  extract_instance.execution_program == 'ConsolidatedItemsV4'
      extract_instance.erp_destination.cds_service_name= 'YY1_BLC_C001'
    end

    #Not all nested relation objects have to be send to SCP
    extractjson = extract_instance.to_json(include: {
        template: {include: :template_lines},
        schedule: {:except => [:segment_configuration_json], include: :schedule_lines},
        definition: {},
        erp_destination: {:except => [:encrypted_password, :encrypted_password_iv]},
        file_destination: {:except => [:encrypted_password, :encrypted_password_iv]},
    })

    parsed_json = JSON(extractjson)

    # set extra fields , runid and blackline instance id
    parsed_json["id"] = extract_instance_db.id
    parsed_json["blackline_instance_id"] = blackline_instance_id
    extractjson = parsed_json.to_json

    return extractjson
  end


  def cancel_extract_job(runname)

    Resque.remove_schedule(runname)

  end



  def schedule_status_job(status_wait, run_id, run_name)

    #TODO Interval check status job Data ingestion
    tenantid = Apartment::Tenant.current

    name = "#{run_name}_#{tenantid}_#{run_id}"
    config = {}
    config[:class] = 'StatusJob'
    config[:cron] = status_wait
    config[:args] = [tenantid.to_s, run_id, name]
    config[:persist] = true
    Resque.set_schedule(name, config)

  end

  def set_error_status(logger, log_message, extract_instance_db, tenant)

    # Setting error status
    logger.log_message('error', "ExtractJob",
                       "Extract Job - Apartment id: #{tenant} #{log_message}")
    extract_instance_db.update_attribute(:status, 7)
  end

  def update_job_status(schedule_instance, extract_instance_db, schedule_id, logger, tenant,status)

    #update job status
    schedule_instance.update_attribute(:scheduled, true)
    schedule_instance.update_attribute(:starttime, Time.now)
    logger.log_message('info', "ExtractJob",
                       "Extract Job - Apartment id: #{tenant} Update status running (3) for Schedule ID : #{schedule_id}")
    extract_instance_db.update_attribute(:status, status)

  end

  def get_new_template(template_db,schedule_instance)

    template = Template.new({
                                definition_id: template_db.definition_id,
                                template_description: template_db.template_description,
                                file_name_prefix: template_db.file_name_prefix,
                                file_name_extension: schedule_instance.file_extension,
                                include_timestamp: template_db.include_timestamp,
                                test_run: template_db.test_run,
                                number_format: template_db.number_format,
                                date_format: template_db.date_format,
                                csv_format: template_db.csv_format,
                                delimiter: template_db.delimiter,
                                line_break: template_db.line_break,
                                csv_quote: template_db.csv_quote,
                                include_header_line: template_db.include_header_line,
                                language_key: template_db.language_key
                            })

    return template
  end



  def get_dev_blackline_instance_id(blackline_instance_id)

    # When the exractor runs on the local machine use blackline instance id 22905
    if blackline_instance_id == "1" and Rails.env.development?
      blackline_instance_id = "22905"
    end

    return blackline_instance_id

  end

  def check_and_get_destination(file_destination_db, logger, template_db, extractdata, connection_profile, tenant)

    if file_destination_db.nil? or template_db.template_description == 'GetExchangeRate'

      logger.log_message('info', "ExtractJob",
                         "Extract Job - Apartment id: #{tenant} No api destination present, finding FTP destination type on connection profile : #{connection_profile.id}")
      file_destination_db = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => extractdata.ftp_destination_type)
    end
    if file_destination_db.nil?

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Apartment id: #{tenant} No FTP destination present, Error on connection profile : #{connection_profile.id}")
    end
    return file_destination_db

  end



  def check_redis_server(logger)

    correct = false

    if ENV['REDIS_SERVER_HOSTS'].nil? and not Rails.env.production?

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Environment variable unavailable : REDIS_SERVER_HOSTS")
    elsif (ENV['REDIS_SERVER_HOSTS'].nil? || ENV['REDIS_SERVER_PASSWORD'].nil?) && Rails.env.production?

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Environment variables unavailable : REDIS_SERVER_HOSTS and/or REDIS_SERVER_PASSWORD")
    elsif ENV['REDIS_SERVER_HOSTS'].empty? and not Rails.env.production?
      logger.log_message('error', "ExtractJob",
                         "Extract Job - Environment variable empty : REDIS_SERVER_HOSTS")
    elsif (ENV['REDIS_SERVER_HOSTS'].empty? || ENV['REDIS_SERVER_PASSWORD'].nil?) && Rails.env.production?

      logger.log_message('error', "ExtractJob",
                         "Extract Job - Environment variables empty : REDIS_SERVER_HOSTS and/or REDIS_SERVER_PASSWORD")
    else
      correct = true
    end
    return correct

  end

  def get_error

    return @error
  end

  def update_functional_log(messages,extract_instance_db)

    job_log_message = ""
    job_log_message = job_log_message + "{\"message\":["

    messages.each do | message |
      job_log_message = job_log_message + "{ \"name\": \"Extractor job error\", \"text\": \"#{message}\"}"
    end

    job_log_message = job_log_message + "]}"

    extract_instance_db.update_attribute(:job_log_message, job_log_message)

  end

  def update_status_extract_run(status,extract_instance_db)

    extract_instance_db.update_attribute(:status, status)

  end

end

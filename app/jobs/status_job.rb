class StatusJob

  @queue = :background

  def self.perform(tenant, runid, name)

    # Set logger
    logger = Rails.logger

    @status_error = 7
    @status_ok = 4
    @minimal_hours_past = 4

    statusjob = StatusJob.new()

    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})

    begin

      Apartment::Tenant.switch!(tenant)

    rescue Exception
      @logger_service.log_message('error', "ExtractJob",
                                  "StatusJob - Tenant: #{tenant} Extractrun Id #{runid} no database or tenant found")
      Resque.remove_schedule(name)
    end

    @logger_service.log_message('info', "StatusJob",
                                "StatusJob - Tenant #{tenant} ExtractHistoryId >> #{runid}")

    if ENV['REDIS_SERVER_HOSTS'].nil? and not Rails.env.production?

      @logger_service.log_message('error', "StatusJob",
                                  "StatusJob - No redis server HOST")
    elsif (ENV['REDIS_SERVER_HOSTS'].nil? || ENV['REDIS_SERVER_PASSWORD'].nil?) && Rails.env.production?

      @logger_service.log_message('error', "StatusJob",
                                  "StatusJob - No redis server production HOST")
    else

      begin
        extract_instance = ExtractRun.find_by(:id => runid)
      rescue Exception
        @logger_service.log_message('error', "ExtractJob",
                                    "StatusJob - Tenant: #{tenant} Extractrun Id #{runid} no database or tenant found")
        Resque.remove_schedule(name)
      end

      if extract_instance.nil?

        #There can not be found a active extract history record. Remove the statusjob.
        @logger_service.log_message('error', "ExtractJob",
                                    "StatusJob - Tenant: #{tenant} Extractrun Id not found #{runid}")
        Resque.remove_schedule(name)
      else

        status = extract_instance.status

        hours_past =  (Time.parse(DateTime.now.to_s) - Time.parse(extract_instance.scheduled_start.to_s))/3600

        if status >= @status_ok
        # Job has already been completed with finished for error status

          Resque.remove_schedule(name)

        #Check if job is running more then 4 hours, if this is the case check the status and update it with a timeout
        # error when the status did not reach the error or finished status.
        elsif hours_past >= @minimal_hours_past

            extract_instance.update_attribute(:status, @status_error)

            statusjob.update_extract_run_log(extract_instance,tenant,runid)

            @logger_service.log_message('error', "ExtractJob",
                                        "StatusJob - Tenant: #{tenant} Extractrun Id #{runid} has a time out or is long running")

            Resque.remove_schedule(name)

        end



      end


    end

  end


  def update_extract_run_log(extract_instance,tenant,runid)

    begin
        extract_instance.update_attribute(:job_log_message, "{\"message\": [{ \"name\": \"Extractor job timeout\", \"text\": \"This run is a long integration run or it has a timeout error\"}]}")
    rescue Exception
      @logger_service.log_message('error', "ExtractJob",
                                  "StatusJob - Tenant: #{tenant} Extractrun Id #{runid} has a time out or is long running and can't update the error status in the run id")
    end

  end

end

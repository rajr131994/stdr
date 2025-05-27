class Api::V1::SapHealthCheckController < Api::V1::ApiBaseController

  skip_before_action :authenticate_api
  skip_before_action :authenticate_scp_api
  skip_before_action :set_connector_instance

  def index

    @logger_service = AppServices::LoggerService.new({log_params: {logger: Rails.logger}})

    message = []
    message << do_resque_scheduler_check
    message << do_btp_extractor_check
    message << extractor_health_check

    error_found = false
    message.each do | error |
      unless error.empty?
        error_found = true
      end
    end

    respond_to do |format|
      if error_found
        format.json { render :json => {"success": false, "message": message}, status: :service_unavailable}
      else
        format.json { render :json => {"success": true, "message": "success"}, status: :ok }
      end
    end

  end


  def do_resque_scheduler_check
    check_result = true
    if Rails.env.production?
      hostname, stderr, status = Open3.capture3("hostname")

      stdout, stderr, status = Open3.capture3("ps aux | grep resque")

      check_result = stdout.include? "resque-pool-master[services.connectors.sap]: managing"

      if check_result == false
        check_result = stdout.include? "Schedules Loaded"
      end
    end

    # Any changes to the below log message to be reviewed for any impact on the newrelic alert configured based on the log message.
    # condition : [`severity` = 'error' AND `source` = 'SapHealthCheckController' AND `message` LIKE '%Resque%']
    @logger_service.log_message('error', "SapHealthCheckController",
                                "Resque scheduler service is not running") unless check_result
    return check_result ? "" : "Resque scheduler service is not running"

  end


  def do_btp_extractor_check
    @logger_service.log_message("info", "SapHealthCheckController", "extractor health check - BTP")
    @restextractor = RestscpData.new(@logger_service, "")

    error =  @restextractor.check_btp_service
    message = @restextractor.get_error_message

    check_result = !error
    @logger_service.log_message('error', "SapHealthCheckController",
                                "BTP extractor service is not running") unless check_result

    return check_result ? "" : "BTP extractor service is not running : #{message}"

  end

  def extractor_health_check
    @logger_service.log_message("info", "SapHealthCheckController", "extractor health check - GKE")
    begin
      @extractor_service = ExtractorService.new(@logger_service, "")
      @extractor_service.health_check
      @logger_service.log_message("info", "SapHealthCheckController", "extractor health check successful")
      return ""
    rescue ExtractorError => ex
      @logger_service.log_message('error', "SapHealthCheckController", "BTP extractor service is not running: #{ex.message}")
      return ex.message
    end
  end


end
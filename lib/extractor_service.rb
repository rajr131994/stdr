require 'blackline_logging'

class ExtractorService

  # TODO SAML for bearer token destination
  attr_accessor :sap_account_info
  attr_accessor :http_request_info

  def initialize(logger_service, tenant)
    @time_out = 1200
    @logger_service = logger_service
    @tenant = tenant
    @errormessage = []

    @air_key = "saptest0"
    if (ENV['SAP_AIR'] != '')
      @air_key = ENV['SAP_AIR']
    end
    @logger_service.log_message('info', "ExtractorService", "tenant: #{@tenant} - targeting extractor backend hosted on GKE.")
  end

  def extractor_token
    token = ""
    begin
      sts_response = HTTParty.post(
        ENV['EXTRACTOR_TOKEN_URI'],
        headers: {
          "Accept" => "application/json",
          "Content-Type" => "application/x-www-form-urlencoded"
        },
        body: {
          "grant_type" => ENV['EXTRACTOR_GRANT_TYPE'],
          "scope" => ENV['EXTRACTOR_STS_SCOPE'],
          "client_id" => ENV['EXTRACTOR_CLIENT_ID'],
          "client_secret" => ENV['EXTRACTOR_CLIENT_SECRET']
        },
        verify: false
      )

      if sts_response.success?
        token = sts_response.parsed_response['access_token']
      end
    rescue HTTParty::Error => e
      @logger_service.log_message('error', "ExtractorService",
                                  "extractor_token - tenant: #{@tenant} HttParty::Error : #{e.message}")
    rescue StandardError => e
      @logger_service.log_message('error', "ExtractorService",
                                  "extractor_token - tenant: #{@tenant} StandardError : #{e.message}")
    rescue Errno::ECONNREFUSED => e
      @logger_service.log_message('error', "ExtractorService",
                                  "extractor_token - tenant: #{@tenant} Error refused : #{e.message}")
    end

    return token
  end

  def update_cds_for_consolidation_extractor(json_payload)
    json_object = JSON(json_payload)
    erp_destination = json_object["erp_destination"]
    erp_destination["cds_service_name"] = "YY1_BLC_C005" if json_object["execution_program"] == "ConsolidatedBalanceSheetAccountsV4"

    json_object.to_json
  end

  # SCP Cloud foundry API
  def sapquery_async(time_out, request_payload)
    options = {
      time_out_in: time_out,
      operation_endpoint: '/api/async/v1',
      method_name: 'sap_query_async',
      app_name: "extractor"
    }

    service_call(request_payload, options)
  end

  # SCP Cloud foundry API
  def sapquery(time_out, extract_json)

    extract_json = update_cds_for_consolidation_extractor(extract_json)

    options = {
      time_out_in: time_out,
      operation_endpoint: '/api/rest/v1',
      method_name: 'sap_query',
      app_name: "extractor"
    }

    service_call(extract_json, options)
  end

  # SCP Cloud foundry API
  def sap_dynamic_fields_query(time_out, request_payload)
    options = {
      time_out_in: time_out,
      operation_endpoint: '/possibleField',
      method_name: 'sap_dynamic_fields_query',
      app_name: "extractor"
    }

    service_call(request_payload, options)
  end

  def sap_curr_fields_query(time_out, request_payload)
    options = {
      time_out_in: time_out,
      operation_endpoint: '/currencyField',
      method_name: 'sap_curr_fields_query',
      app_name: "extractor"
    }

    service_call(request_payload, options)
  end

  def sap_scc_fields_query(time_out, request_payload)
    options = {
      time_out_in: time_out,
      operation_endpoint: '/sccField',
      method_name: 'sap_scc_fields_query',
      app_name: "extractor"
    }

    service_call(request_payload, options)
  end

  def get_time_out_default
    @logger_service.log_message('info', "ExtractorService",
                                "get_time_out_default - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    @time_out
  end

  def sap_journal_entry(time_out_in, request_payload, operation_endpoint)

    options = {
      time_out_in: time_out_in,
      operation_endpoint: operation_endpoint,
      method_name: 'sap_journal_entry',
      app_name: "journals"
    }

    service_call(request_payload, options)
  end

  def service_call(request_payload, options = {})

    time_out_in = options[:time_out_in]
    operation_endpoint = options[:operation_endpoint]
    app_name = options[:app_name]
    method_name = options[:method_name]
    # headers = options[:headers]

    @errormessage = []
    error = false
    response = nil
    ###
    time_out = time_out_in.nil? || time_out_in == 0 ? get_time_out_default : time_out_in
    host_uri = app_name == 'journals' ? ENV['JOURNALS_HOST_URI'] : ENV['EXTRACTOR_HOST_URI']
    token = app_name == 'journals' ? "journals_token" : extractor_token

    if (token.nil? || token.empty?) and Rails.env.production?
      @logger_service.log_message('error', "ExtractorService", "service_call - #{method_name} - tenant: #{@tenant} Token not granted. Request can't be processed...")
      @error = true
      @errormessage << "Could not obtain a auth token for extractor service."
      return
    end

    start_time = Time.now
    begin
      trace_id = NewRelic::Agent::Tracer.current_trace_id

      response = HTTPartyWithLogging.post(
        host_uri + operation_endpoint,
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json", "Application-Interface-Key" => @air_key, "traceid" => trace_id },
        body: request_payload,
        timeout: time_out.to_i,
      )

    rescue Net::ReadTimeout
      end_time = Time.now
      error = true
      @logger_service.log_message('error', "ExtractorService", "service_call - #{method_name} - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{end_time - start_time}")
    rescue SocketError => e
      end_time = Time.now
      error = true
      @logger_service.log_message('error', "ExtractorService", "service_call - #{method_name} - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{end_time - start_time}")
    rescue Errno::ECONNREFUSED => e
      end_time = Time.now
      error = true
      @logger_service.log_message('error', "ExtractorService", "service_call - #{method_name} - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{end_time - start_time}")
    else
      end_time = Time.now
      @logger_service.log_message('info', "ExtractorService", "service_call - #{method_name} - tenant: #{@tenant} Success Time elapsed seconds : #{end_time - start_time}")
    end

    unless error
      error = response_http_client(response, "#{app_name} service")
    end

    if !error
      @logger_service.log_message('info', "ExtractorService", "service_call - #{method_name} - tenant: #{@tenant} Success")
      @error = false
      @message = response.body
      return response
    else
      @logger_service.log_message('error', "ExtractorService", "service_call - #{method_name} - tenant: #{@tenant} Error")
      @error = true
    end

    return response
  end

  def get_message
    return @message
  end

  # Connectivity check services
  # Check Extractor service
  def health_check
    host_uri = ENV['EXTRACTOR_HOST_URI']

    token = extractor_token

    if token.nil? || token.empty?
      @logger_service.log_message('error', "ExtractorService", "health_check - tenant: #{@tenant} Token not granted. Request can't be processed...")
      raise ExtractorError, "Could not obtain a auth token for extractor service."
    end

    starttime = Time.now
    begin
      trace_id = NewRelic::Agent::Tracer.current_trace_id

      response = HTTPartyWithLogging.get(
        host_uri + '/health_check',
        headers: { "Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key, "traceid" => trace_id }
      )

    rescue Net::ReadTimeout
      endtime = Time.now
      @logger_service.log_message('error', "ExtractorService", "health_check - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
      raise ExtractorError, "An error has occurred on the Extractor service, connection timeout"

    rescue SocketError => e
      endtime = Time.now
      @logger_service.log_message('error', "ExtractorService", "health_check - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
      raise ExtractorError, "An error has occurred on the Extractor service, http socket error."

    rescue Errno::ECONNREFUSED => e
      endtime = Time.now
      @logger_service.log_message('error', "ExtractorService", "health_check - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
      raise ExtractorError, "An error has occurred on the Extractor service, the connection has been refused."
    else
      endtime = Time.now
      @logger_service.log_message('info', "ExtractorService", "health_check - tenant: #{@tenant} Success - Time elapsed seconds : #{endtime - starttime}")
    end

    if response.nil?
      raise ExtractorError, "Received no response from Extractor service."
    end

    error = response_http_client(response, "extractor service")
    if error
      raise ExtractorError, "Error in Extractor service. HTTP status : #{response.code}"
    end

  end

  # SCP Check Ruby
  def check_ruby(time_out, request_payload)
    options = {
      time_out_in: time_out,
      operation_endpoint: '/v1/connectivity_check/check_ruby',
      method_name: 'check_ruby',
      app_name: "extractor"
    }

    service_call(request_payload, options)
  end

  # SCP Check S4Hana
  def check_s4hana(time_out, request_payload)
    options = {
      time_out_in: time_out,
      operation_endpoint: '/v1/connectivity_check/check_s4hana',
      method_name: 'check_s4hana',
      app_name: "extractor"
    }

    service_call(request_payload, options)
  end

  # SCP Check minimum requirement
  def check_minimum_requirement(time_out, request_payload)
    options = {
      time_out_in: time_out,
      operation_endpoint: '/v1/connectivity_check/check_minimal_requirement',
      method_name: 'check_minimum_requirement',
      app_name: "extractor"
    }

    service_call(request_payload, options)
  end

  # SCP Check SFTP Server
  def check_sftp_server(time_out, request_payload)
    options = {
      time_out_in: time_out,
      operation_endpoint: '/v1/connectivity_check/check_sftp_server',
      method_name: 'check_sftp_server',
      app_name: "extractor"
    }

    service_call(request_payload, options)
  end

  def response_http_client(response, service)
    response_code = response.code

    if response_code.nil?
      @logger_service.log_message('error', "ExtractorService",
                                  "response_http_client - tenant: #{@tenant} Error in #{service} no response")
      @errormessage << "Error in SCP service  http status : unknown"
      return false
    end

    case response_code
    when 200..203
      return false
    when 401
      @errormessage << "Error in #{service}: Invalid credentials"
      @logger_service.log_message('error', "ExtractorService",
                                  "response_http_client- tenant: #{@tenant} Error in #{service} http status : #{response_code}")
      return true
    else
      response_text = response.body
      if response_text.include? "success" and response_text.include? "message"
        message = JSON.parse(response.body)["message"]
      else
        message = response.body
      end
      @errormessage << (response.body.nil? ? "Error in BTP #{service}: HTTP status : #{response_code}" : message)
      @logger_service.log_message('error', "ExtractorService",
                                  "response_http_client- tenant: #{@tenant} Error in #{service} http status : #{response_code}")
      @logger_service.log_message('error', "ExtractorService", "Error message : #{message}")
      return true
    end
  end

  def get_error_message
    @errormessage
  end

  def get_error
    @error
  end

end

require 'blackline_logging'

class RestscpData


  # TODO SAML for bearer token destination
  attr_accessor :sap_account_info
  attr_accessor :http_request_info


  def initialize(logger_service, tenant)
    @time_out = 1200
    @logger_service = logger_service
    @tenant = tenant


    @air_key = "saptest0"
    if (ENV['SAP_AIR'] != '')
      @air_key = ENV['SAP_AIR']
    end
    @logger_service.log_message('info', "RestSCPData", "tenant: #{@tenant} - targeting extractor backend hosted on BTP.")
  end

  #SCP Cloud foundry Token API
  def saptoken(scp_connection, subdomain)

    account_info_saptoken = {
        prefix_uri: 'https://',
        base_uri: scp_connection.token_host,
        endpoint_uri: scp_connection.token_endpoint,
        client_id: scp_connection.client_id_extractor,
        client_secret: scp_connection.client_secret_extract,
        subdomain: subdomain
    }

    if subdomain.nil?
      subdomain = scp_connection.region_code.downcase + 'service' + scp_connection.environment_type.downcase + scp_connection.node
    end

    scp_token = ""
    begin
      response = HTTPartyWithLogging.post(
          account_info_saptoken[:prefix_uri] +
              subdomain + "." + account_info_saptoken[:base_uri] + account_info_saptoken[:endpoint_uri],
          query: {:grant_type => "client_credentials", :response_type => "token"},
          basic_auth: {:username => scp_connection.client_id_extractor, :password => scp_connection.client_secret_extract}
      )
    rescue HTTParty::Error => e

      @logger_service.log_message('error', "RestSCPData",
                                  "saptoken - tenant: #{@tenant} HttParty::Error : #{e.message}")
      return scp_token
    rescue StandardError => e

      @logger_service.log_message('error', "RestSCPData",
                                  "saptoken - tenant: #{@tenant} StandardError : #{e.message}")
      return scp_token
    rescue Errno::ECONNREFUSED => e

      @logger_service.log_message('error', "RestSCPData",
                                  "saptoken - tenant: #{@tenant} Error refused : #{e.message}")
      return scp_token

    end

    @error = response_http_client(response, "extractor token")
    if not response.body.nil?

      scp_token = response.parsed_response["access_token"]
    else
      @logger_service.log_message('error', "RestSCPData",
                                  "saptoken - tenant: #{@tenant} No response from SCP token extractor service")
    end

    return scp_token
  end

  #SCP Cloud foundry API
  def sapquery_async(time_out, extractjson)

    @errormessage = []

    if time_out.nil? or time_out == 0
      time_out = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "sapquery_async - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    end

    response = nil
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      error = false
      subdomain = get_scp_subdomain(scp_connection.node)

      token = saptoken(scp_connection, subdomain)

      if token.nil? || token.empty?
        error = true
        @logger_service.log_message('error', "RestSCPData",
                                    "sapquery_async - tenant: #{@tenant} Token not granted")
      end

      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        scp_connection.host_endpoint_extractor, = "/api/async/v1"
        error = false
        token = ""
        @error = false
      end

      if error == false

        starttime = Time.now

        begin

          response = HTTPartyWithLogging.post(
              scp_connection.host_extractor + '/api/async/v1',
              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key },
              body: extractjson,
              timeout: time_out.to_i
          )

        rescue Net::ReadTimeout

          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "sapquery_async - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")

        rescue SocketError => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "sapquery_async - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")

        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
          else

          endtime = Time.now
          @logger_service.log_message('info', "RestSCPData",
                                      "sapquery_async - tenant: #{@tenant} No timeout - Time elapsed seconds : #{endtime - starttime}")
          end

        if error == false
          error = response_http_client(response, "extractor service")

        end
      end

      if error == false

        @logger_service.log_message('info', "RestSCPData",
                                    "sapquery_async - tenant: #{@tenant} Success running on node : #{scp_connection.node}")
        #@error = false
        return response
      else

        @errormessage << "No scp connections with extractor service on node available"
        @logger_service.log_message('error', "RestSCPData",
                                    "sapquery_async - tenant: #{@tenant} Error running on node : #{scp_connection.node}")
        @error = true
      end

    end

    return response
  end


  #SCP Cloud foundry API
  def sapquery(time_out, extractjson)

    @errormessage = []

    if time_out.nil? or time_out == 0
      time_out = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "sapquery - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    end

    response = ""
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      @errormessage = []
      error = false
      subdomain = get_scp_subdomain(scp_connection.node)
      response = nil

      @account_info_sapinfo = {
          base_uri: scp_connection.host_extractor,
          endpoint_uri: scp_connection.host_endpoint_extractor,
          timeout: time_out.to_i,
          app_key: ""
      }

      token = saptoken(scp_connection, subdomain)

      if token.nil? || token.empty?
        error = true
        @errormessage << "SCP extracter service token not granted"
        @logger_service.log_message('error', "RestSCPData",
                                    "sapquery - tenant: #{@tenant} Token not granted")

      end

      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        scp_connection.host_endpoint_extractor, = "/api/rest/v1"
        error = false
        token = ""
        @error = false
        @errormessage = []
      end

      if error == false

        starttime = Time.now
        begin

          response = HTTPartyWithLogging.post(

              scp_connection.host_extractor + scp_connection.host_endpoint_extractor,

              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key, "Keep-Alive" => "timeout=60000, max=1000"},
              body: extractjson,
              timeout: time_out.to_i,
          )
        rescue Net::ReadTimeout

          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sapquery - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue SocketError => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sapquery - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        else
          endtime = Time.now

          @logger_service.log_message('info', "RestSCPData",
                                      "sapquery - tenant: #{@tenant} Success Time elapsed seconds : #{endtime - starttime}")
        end

        if error == false
          error = response_http_client(response, "extractor service")

        end
      end

      if error == false

        @logger_service.log_message('info', "RestSCPData",
                                    "sapquery - tenant: #{@tenant} Success running on node : #{scp_connection.node} with subdomain : #{subdomain}")
        #@error = error
        return response
      else

        if not response.nil?
          @errormessage << response["job_log_message"]
        else
          @errormessage << "No response"
        end

        @logger_service.log_message('error', "RestSCPData",
                                    "sapquery - tenant: #{@tenant} Error running on node : #{scp_connection.node} with subdomain : #{subdomain}")
      end

    end

    if not @errormessage.empty?
      @error = true
    end

    return response
  end


  #SCP Cloud foundry API
  def sap_dynamic_fields_query(time_out, fieldjson)

    logger = Rails.logger

    connection_profile_service = AppServices::ConnectionProfileService.new({connection_profile_params: {
        type: @type, logger: logger}})

    @errormessage = []

    if time_out.nil? or time_out == 0
      time_out = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "sapquery - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    end

    response = ""
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      @errormessage = []
      error = false
      subdomain = get_scp_subdomain(scp_connection.node)

      @account_info_sapinfo = {
          #prefix_uri: 'https:',
          base_uri: scp_connection.host_extractor,
          endpoint_uri: "/possibleField",
          timeout: time_out.to_i,
          app_key: ""
      }

      token = saptoken(scp_connection, subdomain)

      if token.nil? || token.empty?
        error = true
        @logger_service.log_message('error', "RestSCPData",
                                    "sap_dynamic_fields_query - tenant: #{@tenant} Token not granted")
      end

      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        scp_connection.host_endpoint_extractor, = "/possibleField"
        error = false
        token = ""
        @error = false
        @error_message = []
      end

      response = nil
      if error == false

        starttime = Time.now
        begin
          response = HTTPartyWithLogging.post(
              scp_connection.host_extractor + @account_info_sapinfo[:endpoint_uri],
              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key},
              body: fieldjson,
              timeout: time_out.to_i,
          )
        rescue Net::ReadTimeout

          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue SocketError => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        else
          endtime = Time.now

          @logger_service.log_message('info', "RestSCPData",
                                      "sap_dynamic_fields_query - tenant: #{@tenant} Success Time elapsed seconds : #{endtime - starttime}")
        end

        if error == false
          error = response_http_client(response, "extractor service")

        end
      end

      if error == false

        @logger_service.log_message('info', "RestSCPData",
                                    "sap_dynamic_fields_query - tenant: #{@tenant} Success running on node : #{scp_connection.node} with subdomain : #{subdomain}")
        return response
      else

        @errormessage << "No scp connections with extractor service on node available"
        @logger_service.log_message('error', "RestSCPData",
                                    "sap_dynamic_fields_query - tenant: #{@tenant} Error running on node : #{scp_connection.node} with subdomain : #{subdomain}")

      end

    end

    if not @errormessage.empty?
      @error = true
    end

    return response
  end

  def sap_curr_fields_query(time_out, fieldjson)

    logger = Rails.logger

    connection_profile_service = AppServices::ConnectionProfileService.new({connection_profile_params: {
        type: @type, logger: logger}})

    @errormessage = []

    if time_out.nil? or time_out == 0
      time_out = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "sapquery - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    end

    response = ""
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      @errormessage = []
      error = false
      subdomain = get_scp_subdomain(scp_connection.node)

      @account_info_sapinfo = {
          #prefix_uri: 'https:',
          base_uri: scp_connection.host_extractor,
          endpoint_uri: "/currencyField",
          timeout: time_out.to_i,
          app_key: ""
      }

      token = saptoken(scp_connection, subdomain)

      if token.nil? || token.empty?
        error = true
        @logger_service.log_message('error', "RestSCPData",
                                    "sap_dynamic_fields_query - tenant: #{@tenant} Token not granted")
      end

      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        scp_connection.host_endpoint_extractor, = "/currencyField"
        error = false
        token = ""
        @error = false
      end

      response = nil
      if error == false

        starttime = Time.now
        begin
          response = HTTPartyWithLogging.post(
              scp_connection.host_extractor + @account_info_sapinfo[:endpoint_uri],
              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key},
              body: fieldjson,
              timeout: time_out.to_i,
              )
        rescue Net::ReadTimeout

          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue SocketError => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        else
          endtime = Time.now

          @logger_service.log_message('info', "RestSCPData",
                                      "sap_dynamic_fields_query - tenant: #{@tenant} Success Time elapsed seconds : #{endtime - starttime}")
        end

        if error == false
          error = response_http_client(response, "extractor service")

        end
      end

      if error == false

        @logger_service.log_message('info', "RestSCPData",
                                    "sap_dynamic_fields_query - tenant: #{@tenant} Success running on node : #{scp_connection.node} with subdomain : #{subdomain}")
        #@error = error
        return response
      else

        @errormessage << "No scp connections with extractor service on node available"
        @logger_service.log_message('error', "RestSCPData",
                                    "sap_dynamic_fields_query - tenant: #{@tenant} Error running on node : #{scp_connection.node} with subdomain : #{subdomain}")

      end

    end

    if not @errormessage.empty?
      @error = true
    end

    return response
  end


  def sap_scc_fields_query(time_out, fieldjson)

    logger = Rails.logger

    connection_profile_service = AppServices::ConnectionProfileService.new({connection_profile_params: {
        type: @type, logger: logger}})

    @errormessage = []

    if time_out.nil? or time_out == 0
      time_out = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "sapquery - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    end

    response = ""
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      @errormessage = []
      error = false
      subdomain = get_scp_subdomain(scp_connection.node)

      @account_info_sapinfo = {
          #prefix_uri: 'https:',
          base_uri: scp_connection.host_extractor,
          endpoint_uri: "/sccField",
          timeout: time_out.to_i,
          app_key: ""
      }

      token = saptoken(scp_connection, subdomain)

      if token.nil? || token.empty?
        error = true
        @logger_service.log_message('error', "RestSCPData",
                                    "sap_dynamic_fields_query - tenant: #{@tenant} Token not granted")
      end

      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        scp_connection.host_endpoint_extractor, = "/sccField"
        error = false
        token = ""
        @error = false
      end

      response = nil
      if error == false

        starttime = Time.now
        begin
          response = HTTPartyWithLogging.post(
              scp_connection.host_extractor + @account_info_sapinfo[:endpoint_uri],
              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key},
              body: fieldjson,
              timeout: time_out.to_i,
              )
        rescue Net::ReadTimeout

          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue SocketError => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "sap_dynamic_fields_query - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        else
          endtime = Time.now

          @logger_service.log_message('info', "RestSCPData",
                                      "sap_dynamic_fields_query - tenant: #{@tenant} Success Time elapsed seconds : #{endtime - starttime}")
        end

        if error == false
          error = response_http_client(response, "extractor service")

        end
      end

      if error == false

        @logger_service.log_message('info', "RestSCPData",
                                    "sap_dynamic_fields_query - tenant: #{@tenant} Success running on node : #{scp_connection.node} with subdomain : #{subdomain}")
        #@error = error
        return response
      else

        @errormessage << "No scp connections with extractor service on node available"
        @logger_service.log_message('error', "RestSCPData",
                                    "sap_dynamic_fields_query - tenant: #{@tenant} Error running on node : #{scp_connection.node} with subdomain : #{subdomain}")

      end

    end

    if not @errormessage.empty?
      @error = true
    end

    return response
  end



  def get_time_out_default(time_out_in)

    if time_out_in.nil? || time_out_in == 0
      time_out_return = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "sapquery - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")

    else
      time_out_return = time_out_in
    end

  end


  def sap_journal_entry(time_out_in, fieldjson, operation_endpoint)

    options = {
      time_out_in: time_out_in,
      operation_endpoint: operation_endpoint,
      app_name: "journals"
    }

    return service_call(fieldjson, options)
  end

  # this service_call method can be reused for other use cases
  # currently this code for calling other services is duplicated in all the methods.
  # existing methods can be refactored one-by-one to make use this common method
  def service_call(request_payload, options = {})

    time_out_in = options[:time_out_in]
    operation_endpoint = options[:operation_endpoint]
    app_name = options[:app_name]
    # headers = options[:headers]

    time_out = get_time_out_default(time_out_in)

    @errormessage = []
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      @errormessage = []
      error = false
      subdomain = get_scp_subdomain(scp_connection.node)
      operation_endpoint = scp_connection.host_endpoint_extractor unless operation_endpoint
      host_uri = app_name == 'journals' ? scp_connection.host_extractor.sub('s4hextractor', 'journals') : scp_connection.host_extractor

      account_info_sapinfo = {
        base_uri: host_uri,
        endpoint_uri: operation_endpoint,
        timeout: time_out.to_i
      }

      token = saptoken(scp_connection, subdomain)
      if token.nil? || token.empty?
        error = true
        @logger_service.log_message('error', "RestSCPData",
                                    "service_call - tenant: #{@tenant} Token not granted")
      end

      response = nil
      if error == false
        # headers["Authorization"] = "Bearer " + token
        starttime = Time.now
        begin
          response = HTTPartyWithLogging.post(
            account_info_sapinfo[:base_uri] + account_info_sapinfo[:endpoint_uri],
            headers: { "Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key },
            body: request_payload,
            timeout: time_out.to_i,
            )

        rescue Net::ReadTimeout
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData", "service_call - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue SocketError => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData", "service_call - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData", "service_call - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        else
          endtime = Time.now
          @logger_service.log_message('info', "RestSCPData", "service_call - tenant: #{@tenant} Success Time elapsed seconds : #{endtime - starttime}")
        end
      end

      if error == false
        error = response_http_client(response, "#{app_name} service")
      end

      if error == false
        @logger_service.log_message('info', "RestSCPData", "service_call - tenant: #{@tenant} Success running on node : #{scp_connection.node}")
        @error = false
        @message = response.body
        return response
      else
        unless response.nil?
          @errormessage << response["job_log_message"]
        end

        @logger_service.log_message('error', "RestSCPData", "service_call - tenant: #{@tenant} Error running on node : #{scp_connection.node}")
        @error = true
      end

    end
  end


  def get_message
    return @message
  end

  # Connectivity check services
  #Check BTP service
  def check_btp_service

    @errormessage = []

    response = nil
    @scp_connections = get_scp_connections("",nil)

    error = false
    error_node_list = []
    @scp_connections.each do |scp_connection|

      token = saptoken(scp_connection, nil)

      if token.nil? || token.empty?
        error = true
        @logger_service.log_message('error', "RestSCPData",
                                    "check_btp_service - tenant: #{@tenant} Token not granted, node: #{scp_connection.node}")
        @errormessage << "An error has occurred on the BTP service, token not granted, node: #{scp_connection.node}"
      end


      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        error = false
        token = ""
        @error = false
      end

        starttime = Time.now
        begin

          response = HTTPartyWithLogging.get(
              scp_connection.host_extractor + '/health_check',
              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key }
          )

        rescue Net::ReadTimeout

          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_btp_service - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
          @errormessage << "An error has occurred on the BTP service, timeout, node: #{scp_connection.node}"

        rescue SocketError => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_btp_service - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
          @errormessage << "An error has occurred on the BTP service, http socket error, node: #{scp_connection.node}"

        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "check_btp_service - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
          @errormessage << "An error has occurred on the BTP service, the connection has been refused, node: #{scp_connection.node}"
        else
          endtime = Time.now
          @logger_service.log_message('info', "RestSCPData",
                                      "check_btp_service - tenant: #{@tenant} No timeout - Time elapsed seconds : #{endtime - starttime}")
          error = true
        end

        if (not response.nil?)
          error = response_http_client(response, "extractor service")

          if error == true
            @errormessage << "Error in BTP service: Unavailable node #{scp_connection.node} HTTP status : #{response.code}"
          end
        else
          #@errormessage << "There has been an error occurred on the BTP service, node: #{scp_connection.node}, no response"
          #error = true

        end

        if error == true
          current_node = scp_connection.node
          error_node_list << current_node
        end

    end

    if @scp_connections.length == error_node_list.length and error == true
      @errormessage << "An error has occurred on the BTP service, no nodes available"
    elsif error_node_list.length > 0
      error = true
    end


    return error
  end

  #SCP Check Ruby
  def check_ruby(time_out, extractjson)

    @errormessage = []

    if time_out.nil? or time_out == 0
      time_out = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "check_ruby - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    end

    response = nil
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      error = false
      subdomain = get_scp_subdomain(scp_connection.node)

      @account_info_sapinfo = {
          #prefix_uri: 'https:',
          base_uri: scp_connection.host_extractor,
          endpoint_uri: '/v1/connectivity_check/check_ruby',
          timeout: time_out.to_i,
          app_key: ""
      }

      token = saptoken(scp_connection, subdomain)

      if token.nil? || token.empty?
        error = true
        @logger_service.log_message('error', "RestSCPData",
                                    "check_ruby - tenant: #{@tenant} Token not granted")
      end


      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        scp_connection.host_endpoint_extractor, = "/v1/connectivity_check/check_ruby"
        error = false
        token = ""
        @error = false
        @errormessage = []
      end

      if error == false

        starttime = Time.now
        begin

          response = HTTPartyWithLogging.post(
              scp_connection.host_extractor + @account_info_sapinfo[:endpoint_uri],
              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key },
              body: extractjson,
              timeout: time_out.to_i
          )


        rescue Net::ReadTimeout

          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_ruby - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")

        rescue SocketError => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_ruby - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "check_ruby - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        else
          endtime = Time.now
          @logger_service.log_message('info', "RestSCPData",
                                      "check_ruby - tenant: #{@tenant} No timeout - Time elapsed seconds : #{endtime - starttime}")

        end

        if error == false
          error = response_http_client(response, "extractor service")

        end
      end

      if error == false

        @logger_service.log_message('info', "RestSCPData",
                                    "check_ruby - tenant: #{@tenant} Success running on node : #{scp_connection.node}")
        @error = false
        return response
      else

        @errormessage << "No scp connections with extractor service on node available"
        @logger_service.log_message('error', "RestSCPData",
                                    "check_ruby - tenant: #{@tenant} Error running on node : #{scp_connection.node}")
        @error = true
      end

    end

    return response
  end


  #SCP Check S4Hana
  def check_s4hana(time_out, extractjson)

    @errormessage = []

    if time_out.nil? or time_out == 0
      time_out = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "check_s4hana - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    end

    response = nil
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      error = false
      subdomain = get_scp_subdomain(scp_connection.node)

      @account_info_sapinfo = {
          #prefix_uri: 'https:',
          base_uri: scp_connection.host_extractor,
          endpoint_uri: '/v1/connectivity_check/check_s4hana',
          timeout: time_out.to_i,
          app_key: ""
      }

      token = saptoken(scp_connection, subdomain)

      if token.nil? || token.empty?
        error = true

        @logger_service.log_message('error', "RestSCPData",
                                    "check_s4hana - tenant: #{@tenant} Token not granted")
      end

      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        scp_connection.host_endpoint_extractor, = "/v1/connectivity_check/check_s4hana"
        error = false
        token = ""
        @error = false
        @errormessage = []
      end

      if error == false

        starttime = Time.now
        begin

          response = HTTPartyWithLogging.post(
              scp_connection.host_extractor + @account_info_sapinfo[:endpoint_uri],
              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key },
              body: extractjson,
              timeout: time_out.to_i
          )

        rescue Net::ReadTimeout

          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_s4hana - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue SocketError => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_s4hana - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_s4hana - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        else
          endtime = Time.now
          @logger_service.log_message('info', "RestSCPData",
                                      "check_s4hana - tenant: #{@tenant} No timeout - Time elapsed seconds : #{endtime - starttime}")
        end

        if error == false
          error = response_http_client(response, "extractor service")

        end
      end

      if error == false

        @logger_service.log_message('info', "RestSCPData",
                                    "check_s4hana - tenant: #{@tenant} Success running on node : #{scp_connection.node}")
        @error = false
        return response
      else
        @errormessage << "No scp connections with extractor service on node available"
        @logger_service.log_message('error', "RestSCPData",
                                    "check_s4hana - tenant: #{@tenant} Error running on node : #{scp_connection.node}")
        @error = true
      end

    end

    return response
  end

  #SCP Check minimum requirement
  def check_minimum_requirement(time_out, extractjson)

    @errormessage = []

    if time_out.nil? or time_out == 0
      time_out = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "check_minimum_requirement - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    end

    response = nil
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      error = false
      subdomain = get_scp_subdomain(scp_connection.node)

      @account_info_sapinfo = {
          #prefix_uri: 'https:',
          base_uri: scp_connection.host_extractor,
          endpoint_uri: '/v1/connectivity_check/check_minimal_requirement',
          timeout: time_out.to_i,
          app_key: ""
      }

      token = saptoken(scp_connection, subdomain)

      if token.nil? || token.empty?
        error = true

        @logger_service.log_message('error', "RestSCPData",
                                    "check_minimum_requirement - tenant: #{@tenant} Token not granted")
      end

      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        scp_connection.host_endpoint_extractor, = "/v1/connectivity_check/check_minimal_requirement"
        error = false
        token = ""
        @error = false
        @errormessage = []
      end

      if error == false

        starttime = Time.now
        begin

          response = HTTPartyWithLogging.post(
              scp_connection.host_extractor + @account_info_sapinfo[:endpoint_uri],
              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key },
              body: extractjson,
              timeout: time_out.to_i
          )


        rescue Net::ReadTimeout

          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_minimum_requirement - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue SocketError => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_minimum_requirement - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_minimum_requirement - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        else
          endtime = Time.now
          @logger_service.log_message('info', "RestSCPData",
                                      "check_minimum_requirement - tenant: #{@tenant} No timeout - Time elapsed seconds : #{endtime - starttime}")
        end

        if error == false
          error = response_http_client(response, "extractor service")

        end
      end

      if error == false

        @logger_service.log_message('info', "RestSCPData",
                                    "check_minimum_requirement - tenant: #{@tenant} Success running on node : #{scp_connection.node}")
        @error = false
        return response
      else
        @errormessage << "No scp connections with extractor service on node available"
        @logger_service.log_message('error', "RestSCPData",
                                    "check_minimum_requirement - tenant: #{@tenant} Error running on node : #{scp_connection.node}")
        @error = true
      end

    end

    return response
  end

  #SCP Check SFTP Server
  def check_sftp_server(time_out, extractjson)

    @errormessage = []

    if time_out.nil? or time_out == 0
      time_out = @time_out
      @logger_service.log_message('info', "RestSCPData",
                                  "check_sftp_server - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
    end

    response = nil
    @scp_connections = get_scp_connections("",nil)

    @scp_connections.each do |scp_connection|

      error = false
      subdomain = get_scp_subdomain(scp_connection.node)

      @account_info_sapinfo = {
          #prefix_uri: 'https:',
          base_uri: scp_connection.host_extractor,
          endpoint_uri: '/v1/connectivity_check/check_sftp_server',
          timeout: time_out.to_i,
          app_key: ""
      }

      token = saptoken(scp_connection, subdomain)

      if token.nil? || token.empty?
        error = true

        @logger_service.log_message('error', "RestSCPData",
                                    "check_sftp_server - tenant: #{@tenant} Token not granted")
      end


      unless Rails.env.production?
        scp_connection.host_extractor = "http://localhost:8080"
        scp_connection.host_endpoint_extractor, = "/v1/connectivity_check/check_sftp_server"
        error = false
        token = ""
        @error = false
        @errormessage = []
      end

      if error == false

        starttime = Time.now
        begin

          response = HTTPartyWithLogging.post(
              scp_connection.host_extractor + @account_info_sapinfo[:endpoint_uri],
              headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key },
              body: extractjson,
              timeout: time_out.to_i
          )


        rescue Net::ReadTimeout

          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_sftp_server - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")

        rescue SocketError => e
          endtime = Time.now
          error = true
          @logger_service.log_message('error', "RestSCPData",
                                      "check_sftp_server - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")

        rescue Errno::ECONNREFUSED => e
          endtime = Time.now
          error = true

          @logger_service.log_message('error', "RestSCPData",
                                      "check_sftp_server - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
        else
          endtime = Time.now
          @logger_service.log_message('info', "RestSCPData",
                                      "check_sftp_server - tenant: #{@tenant} No timeout - Time elapsed seconds : #{endtime - starttime}")

        end

        if error == false
          error = response_http_client(response, "extractor service")

        end
      end

      if error == false

        @logger_service.log_message('info', "RestSCPData",
                                    "check_sftp_server - tenant: #{@tenant} Success running on node : #{scp_connection.node}")
        @error = false
        return response
      else

        @errormessage << "No scp connections with extractor service on node available"
        @logger_service.log_message('error', "RestSCPData",
                                    "check_sftp_server - tenant: #{@tenant} Error running on node : #{scp_connection.node}")
        @error = true
      end

    end

    return response
  end


  #SCP Cloud foundry API FA service
  # def sap_fa_service(time_out, fieldjson, connection_profile, hostname, blackline_instance_id)
  #
  #   logger = Rails.logger
  #
  #   connection_profile_service = AppServices::ConnectionProfileService.new({connection_profile_params: {
  #       type: @type, logger: logger}})
  #
  #   @errormessage = []
  #
  #   if time_out.nil? or time_out == 0
  #     time_out = @time_out
  #     @logger_service.log_message('info', "RestSCPData",
  #                                 "sapquery - tenant: #{@tenant} Timeout value not present. Set to default: #{@time_out}")
  #   end
  #
  #   response = ""
  #   @scp_connections = get_scp_connections("",nil)
  #
  #   @scp_connections.each do |scp_connection|
  #
  #     error = false
  #     subdomain = get_scp_subdomain(blackline_instance_id, scp_connection.node, hostname)
  #
  #     @account_info_sapinfo = {
  #         #prefix_uri: 'https:',
  #         base_uri: scp_connection.host_extractor,
  #         endpoint_uri: "/possibleField",
  #         timeout: time_out.to_i,
  #         app_key: ""
  #     }
  #
  #     token = saptoken(scp_connection, subdomain)
  #
  #     if @error == true
  #       #return response
  #     end
  #
  #     if token.nil? || token.empty?
  #       error = true
  #       @logger_service.log_message('error', "RestSCPData",
  #                                   "sap_dynamic_fields_query - tenant: #{@tenant} Token not granted")
  #     else
  #       #logger.info("sapquery - Token granted ")
  #     end
  #
  #     response = nil
  #     if error == false
  #
  #       # Check if destination name exists
  #       destination_name = JSON.parse(fieldjson)["erp_destination"]["destination_name"]
  #
  #       response = destination_recovery(connection_profile, hostname, blackline_instance_id, destination_name, connection_profile_service,scp_connection.node)
  #
  #       if @error == true
  #         #return response
  #       end
  #
  #       starttime = Time.now
  #       begin
  #         response = HTTPartyWithLogging.post(
  #             scp_connection.host_extractor + @account_info_sapinfo[:endpoint_uri],
  #             headers: {"Authorization" => "Bearer " + token, "Content-Type" => "application/json", "Application-Interface-Key" => @air_key},
  #             body: fieldjson,
  #             timeout: @account_info_sapinfo[:timeout]
  #         )
  #       rescue Net::ReadTimeout
  #
  #         endtime = Time.now
  #         error = true
  #
  #         @logger_service.log_message('error', "RestSCPData",
  #                                     "sap_dynamic_fields_query - Net::ReadTimeout tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
  #       rescue SocketError => e
  #         endtime = Time.now
  #         error = true
  #
  #         @logger_service.log_message('error', "RestSCPData",
  #                                     "sap_dynamic_fields_query - SocketError tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
  #       rescue Errno::ECONNREFUSED => e
  #         endtime = Time.now
  #         error = true
  #
  #         @logger_service.log_message('error', "RestSCPData",
  #                                     "sap_dynamic_fields_query - Connection refused tenant: #{@tenant} Timeout - Time elapsed seconds : #{endtime - starttime}")
  #       else
  #         endtime = Time.now
  #
  #         @logger_service.log_message('info', "RestSCPData",
  #                                     "sap_dynamic_fields_query - tenant: #{@tenant} Success Time elapsed seconds : #{endtime - starttime}")
  #       end
  #
  #       if error == false
  #         error = response_http_client(response.code, "extractor service")
  #
  #       end
  #     end
  #
  #     if error == false
  #
  #       @logger_service.log_message('info', "RestSCPData",
  #                                   "sap_dynamic_fields_query - tenant: #{@tenant} Success running on node : #{scp_connection.node} with subdomain : #{subdomain} on hostname: #{hostname}")
  #       @error = error
  #       return response
  #     else
  #       @errormessage << "No scp connections with extractor service on node available on subdomain: #{subdomain}"
  #       @logger_service.log_message('error', "RestSCPData",
  #                                   "sap_dynamic_fields_query - tenant: #{@tenant} Success running on node : #{scp_connection.node} with subdomain : #{subdomain} on hostname: #{hostname}")
  #
  #     end
  #
  #   end
  #
  #   return response
  # end



  def get_scp_connections(hostname,node)

    environment = ENV["SCP_ENV_TYPE"].upcase

    if environment.nil?
      @logger_service.log_message('error', "RestSCPData",
                                  "get_scp_connections - No environment variable found: SCP_ENV_TYPE")
    elsif environment.empty?
      @logger_service.log_message('error', "RestSCPData",
                                  "get_scp_connections - No environment variable: SCP_ENV_TYPE is empty")
    end

    if ENV["BL_ENV_NAME"].include? "eu"
      region_code = "EU"
    else
      region_code = "US"
    end

    if node.nil?
      @scp_connections = ScpConnection.where(region_code: region_code, environment_type: environment, active: true).order(:node)
    else
      @scp_connections = ScpConnection.where(region_code: region_code, environment_type: environment, active: true,node: node).order(:node)
    end

    if @scp_connections.nil? || @scp_connections.empty?
      @logger_service.log_message('error', "RestSCPData",
                                  "get_scp_connections - No active ScpConnection records found with region_code : #{region_code} environment: #{environment}")

      @errormessage << "No active ScpConnection records found with region_code : #{region_code} environment: #{environment}"
      @error = true
    end

    return @scp_connections

  end

  def get_scp_subdomain(node)

    environment = ENV["SCP_ENV_TYPE"].upcase

    if ENV["BL_ENV_NAME"].include? "eu"
      region_code = "EU"

    else
      region_code = "US"

    end

    if environment.nil?
      @logger_service.log_message('error', "RestSCPData",
                                  "get_scp_subdomain - No enviroment variable found : SCP_ENV_TYPE")
    elsif environment.empty?
      @logger_service.log_message('error', "RestSCPData",
                                  "get_scp_subdomain - Enviroment variable : SCP_ENV_TYPE is empty")
    end

    if node.nil?
      @logger_service.log_message('error', "RestSCPData",
                                  "get_scp_subdomain - Node number is not present")
    elsif node.empty?
      @logger_service.log_message('error', "RestSCPData",
                                  "get_scp_subdomain - Node number is empty")
    end

    service_name = "SERVICE"

    return region_code + service_name + environment + node

  end

  def response_http_client(response, service)
    response_code = response.code

    if response_code.nil?
      @logger_service.log_message('error', "RestSCPData",
                                  "response_http_client - tenant: #{@tenant} Error in #{service} no response")
      @errormessage = "Error in SCP service  http status : unknown"
      return false
    else

      case response_code
      when 200..203
        return false
      when 401
        @errormessage << "Error in BTP #{service}: autorisation credentials error on BTP"
        @logger_service.log_message('error', "RestSCPData",
                                    "response_http_client- tenant: #{@tenant} Error in #{service} http status : #{response_code}")
        return true
      when 404
        # @errormessage << "Error in BTP #{service}: Requested route does not exist."
        @logger_service.log_message('error', "RestSCPData",
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
        @logger_service.log_message('error', "RestSCPData",
                                    "response_http_client- tenant: #{@tenant} Error in #{service} http status : #{response_code}")
        return true
      end
    end
  end


  def get_error_message

    return @errormessage
  end

  def get_error

    return @error
  end


end

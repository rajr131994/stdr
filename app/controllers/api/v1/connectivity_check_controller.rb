class Api::V1::ConnectivityCheckController < Api::V1::ApiBaseController

  before_action :set_connection_profile_object, only: [:show ]

  def index

    respond_to do |format|

        format.json { render :json => {"success": true, "message": "OK"} }

    end

  end


  def show

    apartment_id = Apartment::Tenant.current
    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})

    @blackline_instance_local = "22905"

    blackline_instance_id = @connector_instance.blackline_instance_id.to_s

    if Rails.env == "development"
      blackline_instance_id = @blackline_instance_local
    end

    connection_profile = @connection_profile

    erp_destination = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => 1)
    conn_check_erp = ConnCheck.new(erp_destination, blackline_instance_id, apartment_id, "", "")
    ftp_destination = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => 2)
    conn_check_ftp = ConnCheck.new(ftp_destination, blackline_instance_id, apartment_id, "", "")
    sap_conn_destination = get_sap_conn_credentials
    conn_check_sap_conn = ConnCheck.new(sap_conn_destination, blackline_instance_id, apartment_id, "", "")

    @restextractor = connection_profile.gke_enabled ? ExtractorService.new(@logger_service,apartment_id)
                                                    : RestscpData.new(@logger_service,apartment_id)

    begin
      # check certificate validity if client cert authentication is used
      if erp_destination.oauth_type == 3
        CertUtils.validate_client_cert(erp_destination.base64_encoded_cert, erp_destination.client_cert_password)
      end
    rescue Exception => ex
      logger.error ex.message
      error = true
      errormessage = {"success" => false, "message" => ex.message}.to_s
      end

    unless error
      conn_check_erp_json = get_s4h_json(conn_check_erp,erp_destination,logger)
      response_s4hana = @restextractor.check_s4hana(2000, conn_check_erp_json.to_json)

      error = @restextractor.get_error
      errormessage = @restextractor.get_error_message

      if error == false and (response_s4hana.include? "Error" or response_s4hana.include? "\"success\": \"false\"" or response_s4hana.include? "\"success\":false")
        error = true
        errormessage = response_s4hana.to_s
      end
    end

    if error == false

      conn_check_erp_json = get_s4h_json(conn_check_erp,erp_destination,logger)

      response_min_require = @restextractor.check_minimum_requirement(2000, conn_check_erp_json.to_json)

      error = @restextractor.get_error
      errormessage = @restextractor.get_error_message
      if error == false and (response_min_require.include? "Error" or response_min_require.include? "\"success\": \"false\"" or response_min_require.include? "\"success\":false")
        error = true
        errormessage = response_min_require.to_s
      end

    end

    if error == false

      conn_check_ftp = get_ftp_json(conn_check_ftp,ftp_destination)

      response_sftp = @restextractor.check_sftp_server(2000, conn_check_ftp.to_json)

      error = @restextractor.get_error
      errormessage = @restextractor.get_error_message
      if error == false and (response_sftp.include? "Error" or response_sftp.include? "\"success\": \"false\"" or response_sftp.include? "\"success\":false")
        error = true
        errormessage = response_sftp.to_s
      end

    end

    if error == false

      conn_check_sap_conn = get_ruby_json(conn_check_sap_conn,apartment_id,blackline_instance_id)

      response_sapconn = @restextractor.check_ruby(2000, conn_check_sap_conn.to_json)

      error = @restextractor.get_error
      errormessage = @restextractor.get_error_message
      if error == false and (response_sapconn.include? "Error" or response_sapconn.include? "\"success\": \"false\"" or response_sapconn.include? "\"success\":false")
        error = true
        errormessage = response_sapconn.to_s
      end

    end

    if error == true

      respond_to do |format|
        format.json { render :json => {"success": false, "message": errormessage}, status: :unprocessable_entity }
      end
    else
      respond_to do |format|
        format.json { render json: {"success": true, "message": "The connection profile check with name #{connection_profile.name} has been passed, no problems found"}, status: :ok }
      end

    end

  end

  def get_s4h_json(conn_check_erp,erp_destination,logger)

    segment_config_service = AppServices::SegmentConfigurationService.new({scc_params: {
        type: 2, logger: logger}})

    conn_check_erp_str  = conn_check_erp.to_json
    conn_check_erp_json = JSON(conn_check_erp_str)
    conn_check_erp_json["destination"]["api_username"] = erp_destination.username
    conn_check_erp_json["destination"]["api_password"] = erp_destination.password
    conn_check_erp_json["destination"]["endpoint"] = erp_destination.service_endpoint + "/"
    conn_check_erp_json["destination"]["api_host"] = erp_destination.api_method + erp_destination.api_host
    conn_check_erp_json["destination"]["ftp_directory"] = erp_destination.directory
    conn_check_erp_json["segments"] = segment_config_service.get_minimal_requirement_conn_check

    selectClause_s4h = "[
        {
            \"sapUuid\": null,
            \"sapParentUuid\": null,
            \"sequence\": 1,
            \"outputField\": \"CompanyCode\",
            \"fieldSource\": null,
            \"fieldSourceText\": null,
            \"fieldSourceValue\": \"CompanyCode\",
            \"fieldType\": null,
            \"fieldTypeText\": null,
            \"outputLength\": 50,
            \"decimalPlaces\": 0,
            \"numberNotGroup\": false,
            \"aggregation\": 1,
            \"aggregationText\": null,
            \"onSelectionScreen\": false,
            \"onOutput\": true
        }
    ]"

    conn_check_erp_json["selectClause"] = JSON(selectClause_s4h)

    return conn_check_erp_json
  end

  def get_ftp_json(conn_check_ftp,erp_destination)

    conn_check_ftp_str  = conn_check_ftp.to_json
    conn_check_ftp_json = JSON(conn_check_ftp_str)
    conn_check_ftp_json["destination"]["api_username"] = erp_destination.username
    conn_check_ftp_json["destination"]["api_password"] = erp_destination.password
    conn_check_ftp_json["destination"]["ftp_directory"] = erp_destination.directory
    conn_check_ftp_json["destination"]["api_host_port"] = erp_destination.server_port
    conn_check_ftp_json["destination"]["api_host"] = erp_destination.ip_server
    conn_check_ftp_json["message"] = "This is message for testing SFTP"

    return conn_check_ftp_json
  end


  def get_ruby_json(conn_check_sap_conn,apartment_id,blackline_instance_id)

    conn_check_sap_conn_str  = conn_check_sap_conn.to_json
    conn_check_sap_conn_json = JSON(conn_check_sap_conn_str)
    conn_check_sap_conn_json["destination"]["api_username"] = ENV["STS_CLIENT_ID"]
    conn_check_sap_conn_json["destination"]["api_password"] = ENV["STS_CLIENT_SECRET"]
    conn_check_sap_conn_json["destination"]["api_host"] = ENV["STS_S4H_API_HOST"]
    conn_check_sap_conn_json["destination"]["api_token_host"] = ENV["STS_TOKEN_HOST"]
    conn_check_sap_conn_json["destination"]["api_token_endpoint"] = ENV["STS_TOKEN_ENDPOINT"]
    conn_check_sap_conn_json["destination"]["api_scope"] = ENV["STS_SCOPE_NAME"]
    conn_check_sap_conn_json["destination"]["endpoint"] = "/api/v1/connectivity_check"
    conn_check_sap_conn_json["tenant"] = apartment_id
    conn_check_sap_conn_json["blackline_instance_id"] = blackline_instance_id

    return conn_check_sap_conn_json
  end

  def get_sap_conn_credentials

    destination = Destination.new()

    destination.api_host = ENV["STS_S4H_API_HOST"]
    destination.api_token_host = ENV["STS_TOKEN_HOST"]
    destination.api_token_endpoint = ENV["STS_TOKEN_ENDPOINT"]

    return destination
  end

#Never trust parameters from the scary internet, only allow the list through
  def conn_check_params

    params.require(:integration).permit(:connection_profile_id )

  end

  def set_connection_profile_object

    if params[:id].to_i != 0

      @connection_profile = ConnectionProfile.find(params[:id])

    end

  end


end

class Api::V1::JournalEntryController < Api::V1::ApiBaseController

  before_action :init_connector_instance, only: [:create]
  before_action :set_connection_profile_object, only: [:create]

  def create

    tenant = Apartment::Tenant.current

    @logger_service = AppServices::LoggerService.new({log_params: {
      logger: logger}})

    blackline_instance_id = @connector_instance.blackline_instance_id.to_s
    if Rails.env == "development"
      blackline_instance_id = @blackline_instance_local
    end

    connection_profile = @connection_profile
    erp_destination = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => 1)
    api_destination = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => 4)
    journal_entry_json = get_journal_entry_json(params["journal_entry"],erp_destination,api_destination)

    @restextractor = connection_profile.gke_enabled ? ExtractorService.new(@logger_service, tenant)
                                                    : ::RestscpData.new(@logger_service, tenant)

    @restextractor.sap_journal_entry("1200", journal_entry_json.to_json, "/api/v1/journal/#{operation}")

    @error = @restextractor.get_error
    @message = @restextractor.get_error_message
    @ok_message = @restextractor.get_message

    respond_to do |format|
      if @error == false
        #format.json { render :json => {"success": true, "message": @ok_message} }
        format.json { render :json => @ok_message }
      else
        format.json { render :json => {"success": false, "message": "The journal entry is not created : #{@message}"}, status: 422 }
      end
    end
  end

  def set_connection_profile_object
    @connection_profile = ConnectionProfile.find_by!({name: conn_profile_name})
  end

  def get_journal_entry_json(journal_entry_json_in,erp_destination,api_destination)

    journal_entry_json_str  = journal_entry_json_in.to_json
    journal_entry_json = JSON(journal_entry_json_str)

    erp_destination = "{
            \"username\": \"#{erp_destination.username}\",
            \"password\": \"#{erp_destination.password}\",
            \"BUSINESS_USERNAME\": \"#{erp_destination.business_user}\",
            \"BUSINESS_PASSWORD\": \"#{erp_destination.business_user_password}\",
            \"api_host\": \"#{erp_destination.api_host}\",
            \"api_method\": \"#{erp_destination.api_method}\",
            \"service_endpoint\": \"#{erp_destination.service_endpoint}\",
            \"base64_encoded_cert\": \"#{erp_destination.base64_encoded_cert}\",
            \"client_cert_password\": \"#{erp_destination.client_cert_password}\"}"

    unless api_destination.nil?
      api_destination = "{
            \"username\": \"#{api_destination.username}\",
            \"password\": \"#{api_destination.password}\",
            \"grant_type\": \"#{api_destination.grant_type}\",
            \"scope\": \"#{api_destination.scope}\",
            \"api_token_endpoint\": \"#{api_destination.api_token_endpoint}\",
            \"basic_auth_user\": \"#{api_destination.basic_auth_username}\",
            \"basic_auth_password\": \"#{api_destination.basic_auth_password}\"}"

      journal_entry_json["api_destination"] = JSON(api_destination)
    end

    journal_entry_json["erp_destination"] = JSON(erp_destination)

    return journal_entry_json
  end

  # ToDo add comments
  def init_connector_instance
    logger.info "initializing connector instance using bl_instance_id retrieved from token..."
    instance_id = @bl_instance_id
    unless instance_id
      raise "Failed to initialize connector instance as the bl_instance_id retrieved from token is null/empty"
    end

    logger.info "fetching the connector_instance_id for instance_id : #{instance_id}"
    connector_instance = ConnectorInstance.find_by!(blackline_instance_id: instance_id)

    logger.info "connector_instance_id : #{connector_instance.id}"
    @connector_instance = connector_instance
    Apartment::Tenant.switch!(connector_instance.id)
  end

  private

  #Never trust parameters from the scary internet, only allow the list through.
  def journal_item_params
    params.require(:header).permit(:status)
  end

  def conn_profile_name
    params.require(:conprofile)
  end

  def operation
    params.require(:operation)
  end

end


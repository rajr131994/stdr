class Api::V1::ConnectionProfilesController < Api::V1::ApiBaseController
#before_action :authenticate_api_with_scope, unless: -> { ENV['RAILS_ENV'].to_s == 'development' }
#skip_before_action :authenticate_api
  before_action :set_connection_profile_object, only: [:show, :update, :destroy]


  def index
    @connection_profiles = ConnectionProfile.all
    prepared_json = @connection_profiles.to_json( :except => [:client_secret, :client_secret_extract, :password,
                                                              :encrypted_password, :encrypted_password_iv, :encrypted_client_secret_extract,
                                                              :encrypted_client_secret_extract_iv, :encrypted_client_secret_dest, :encrypted_client_secret_dest_iv,
                                                              :client_secret_dest ],
                                                  include: {
                                                    destinations: {:except => [:client_secret, :password,
                                                                               :encrypted_password, :encrypted_password_iv, :encrypted_client_secret,
                                                                               :encrypted_client_secret_iv, :encrypted_client_secret,
                                                                               :encrypted_business_user_password_iv, :encrypted_business_user_password, :business_user_password,
                                                                               :encrypted_client_cert_password, :encrypted_client_cert_password_iv, :basic_auth_password,
                                                                               :encrypted_token, :encrypted_token_iv ] }})

    connection_profiles = JSON.parse(prepared_json)
    erp_destinations = connection_profiles.flat_map do |cp|
      cp['destinations'].select { |d| d['destination_type'] == 1 }  # erp destination type = 1
    end

    erp_destinations.each do |erp_destination|
      begin
        unless erp_destination['base64_encoded_cert'].nil? or erp_destination['base64_encoded_cert'].empty? or
                erp_destination['client_cert_password'].nil? or erp_destination['client_cert_password'].empty?
          erp_destination['client_cert_info'] = CertUtils.get_cert_details(erp_destination['base64_encoded_cert'], erp_destination['client_cert_password'])
        end

        excluded_attributes = %w[ base64_encoded_cert client_cert_password]
        excluded_attributes.each { |excluded_attr| erp_destination.delete(excluded_attr) }
      rescue Exception => ex
        logger.error "failed to unpack the certificates for destination #{erp_destination['destination_name']}: #{ex.message}"
      end
    end

    respond_to do |format|
     format.json { render :json => connection_profiles.to_json, status: :ok }
    end

end

def show

  prepared_json = @connection_profile.to_json( :except => [:client_secret, :client_secret_extract, :password,
                                                           :encrypted_password, :encrypted_password_iv, :encrypted_client_secret_extract,
                                                           :encrypted_client_secret_extract_iv, :encrypted_client_secret_dest, :encrypted_client_secret_dest_iv,
                                                           :client_secret_dest ],
                                               include: {
                                                 destinations: {:except => [:client_secret, :password,
                                                                            :encrypted_password, :encrypted_password_iv, :encrypted_client_secret,
                                                                            :encrypted_client_secret_iv, :encrypted_client_secret,
                                                                            :encrypted_business_user_password_iv, :encrypted_business_user_password, :business_user_password,
                                                                            :encrypted_client_cert_password, :encrypted_client_cert_password_iv, :basic_auth_password,
                                                                            :encrypted_token, :encrypted_token_iv ] }})

  parsed_cp = JSON.parse(prepared_json)
  erp_destination = parsed_cp['destinations'].find { |d| d['destination_type'] == 1 } # erp destination type = 1
  begin
    unless erp_destination['base64_encoded_cert'].nil? or erp_destination['base64_encoded_cert'].empty? or
            erp_destination['client_cert_password'].nil? or erp_destination['client_cert_password'].empty?
      erp_destination['client_cert_info'] = CertUtils.get_cert_details(erp_destination['base64_encoded_cert'], erp_destination['client_cert_password'])

      excluded_attributes = %w[ base64_encoded_cert client_cert_password]
      excluded_attributes.each { |excluded_attr| erp_destination.delete(excluded_attr) }
    end
  rescue Exception => ex
      logger.error ex.message
  end

  connection_profile_json = parsed_cp.to_json

  respond_to do |format|
    format.json { render :json => connection_profile_json.html_safe, status: :ok }

  end

end
 
def create

  @logger_service = AppServices::LoggerService.new({log_params: {
      logger: logger}})

  connection_profile= params.to_json
  tenant = Apartment::Tenant.current

  @error = false
  @errormessage = []
  json_connection_profile = JSON.parse(connection_profile)

  connection_profile_service = AppServices::ConnectionProfileService.new({ connection_profile_params: {
      type:   @type, logger: logger  } } )

  if connection_profile_params[:name].nil?

    @logger_service.log_message('error', "ConnectionProfile",
                                         "create -  Tenant : #{tenant} Error Connection profile name needs to be supplied")
    raise ActionController::ParameterMissing, "Connection profile name needs to be supplied"
  else
    #logger.info "connection_profile_controller - create - Connection profile name needs to be supplied id : #{connection_profile_params[:name]}"
  end

  connection_profile_id = connection_profile_service.save_connection_profile(json_connection_profile,connection_profile_params,logger)

  @error = connection_profile_service.get_error
  @errormessage = connection_profile_service.get_error_message

   if @error == false
      respond_to do |format|
        format.json {render :json => {"success": true,"message": "Created", "connProfileId": connection_profile_id }, status: 201}
      end
   else
    respond_to do |format|
      format.json {render :json => {"success": false,"message": @errormessage }, status: 500}
    end
   end


end

def destroy

  @error = false
  @errormessage = []

  connection_profile_service = AppServices::ConnectionProfileService.new({ connection_profile_params: {
      type:   @type, logger: logger  } } )

  connection_profile_service.delete_connection_profile(@connection_profile)

  @error = connection_profile_service.get_error
  @errormessage = connection_profile_service.get_error_message

  if @error == false
    respond_to do |format|
      format.json {render :json => {"success": true, "message": "Deleted"}, status: :ok}
    end
  else
    respond_to do |format|
      format.json {render :json => {"success": false, "message": @errormessage}, status: 500}
    end
  end

end


def update

  @error = false
  @errormessage = ""

  connection_profile_service = AppServices::ConnectionProfileService.new({ connection_profile_params: {
      type:   @type, logger: logger  } } )

  connection_profile = params.to_json

  json_connection_profile = JSON.parse(connection_profile)

  if json_connection_profile["name"].nil? || json_connection_profile["name"].empty?
    raise ActiveRecord::StatementInvalid, "Connection profile name needs to be supplied"
  end

  update_destinations = Destination.where(:connection_profile_id => @connection_profile.id)

  if update_destinations.nil?
    raise ActiveRecord::StatementInvalid, "No destinations found in connection profile: #{json_connection_profile["name"]}"
  end

  connection_profile_service.update_connection_profile(json_connection_profile,@connection_profile,update_destinations)

  @error = connection_profile_service.get_error
  @errormessage = connection_profile_service.get_error_message

  if @error == false
    respond_to do |format|
      format.json {render :json => {"success": true, "message": "Updated"}, status: :ok}
    end
  else
    respond_to do |format|
      format.json {render :json => {"success": false, "message": @errormessage}, status: 500}
    end
  end

end

def set_connection_profile_object

  @connection_profile = ConnectionProfile.find(params[:id])

end

private

#Never trust parameters from the scary internet, only allow the list through
def connection_profile_params

  params.require(:connection_profile).permit(:name, :token_host, :token_endpoint, :subdomain, :username, :password, :gke_enabled,
                                             :host_destination, :host_endpoint_destination, :client_id_destination, :client_secret_dest,
                                             :host_extractor, :host_endpoint_extractor, :client_id_extractor, :client_secret_extract, :default_connection_profile,
                                             destinations: [:connection_profile_id, :destination_name, :destination_description,
                                                            :active, :configured, :running, :is_consistent, :destination_type, :service_endpoint, :oauth_type,
                                                            :api_method, :api_host, :username, :password, :api_key, :update_flag, :location_id, :proxy_type])

end




end
class Api::V1::JobSchedulerController < Api::V1::ApiBaseController


  def show

    tenant = Apartment::Tenant.current

    service_name = extractrun_params[:service_name]
    connection_profile_id = extractrun_params[:connection_profile_id]

    blackline_instance_id = @connector_instance.blackline_instance_id.to_s

    connection_profile = ConnectionProfile.find(connection_profile_id)
    erp_destination = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => 1)

    @restextractor = connection_profile.gke_enabled ? ExtractorService.new(@logger_service, tenant)
                                                    : ::RestscpData.new(@logger_service,tenant)

    response = @restextractor.sap_fa_service(nil,{:destination_name => erp_destination.destination_name,:service_name => service_name, :task => ""},connection_profile,"",blackline_instance_id)

    respond_to do |format|
      format.json { render json: response }
    end

  end


  def extractrun_params

    params.permit( :service_name,  :connection_profile_id)

  end


end


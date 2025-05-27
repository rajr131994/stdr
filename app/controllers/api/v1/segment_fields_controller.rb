class Api::V1::SegmentFieldsController < Api::V1::ApiBaseController

  def index

    @error_message = []
    @error = false

    segment_config_service = AppServices::SegmentConfigurationService.new({ scc_params: {
        type:   @type, logger: logger } })

    reason_code_scc = segment_config_service.get_scc_reason_code

    if segment_fields_params[:reason_code].nil? or
        segment_fields_params[:reason_code].empty?
      reason_code = reason_code_scc
    elsif segment_fields_params[:reason_code] == reason_code_scc
      reason_code = reason_code_scc
    else
      reason_code = segment_fields_params[:reason_code]
    end

    connection_profile = ConnectionProfile.find_by(:default_connection_profile => true)
    erp_destination = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => 1)

    if connection_profile.nil?

      @error_message << "There is no default connection profile configured"
      @error = true
    elsif erp_destination.nil?

      @error_message << "There are no required S4H credentials found in the connection profile"
      @error = true
    end

    if reason_code == reason_code_scc
      #segment_fields = segment_config_service.get_segment_fields
      segment_fields = segment_config_service.get_scc_fields(reason_code,connection_profile,@connector_instance.blackline_instance_id.to_s,erp_destination )
    elsif @error == false

      segment_fields = segment_config_service.get_dynamic_fields(reason_code,connection_profile,@connector_instance.blackline_instance_id.to_s,erp_destination )
    end

    @error = segment_config_service.get_error
    @error_message = segment_config_service.get_error_message

    if @error == true
      respond_to do |format|
        format.json { render :json => {"success": false, "message": @error_message}, status: :unprocessable_entity }
      end
    else
      respond_to do |format|
        format.json { render json: segment_fields, status: :ok }
      end
    end
  end

  def segment_fields_params

    params.permit( :reason_code)

  end



end

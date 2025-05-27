class Api::V1::SegmentFieldsConfigsController < Api::V1::ApiBaseController

  def show

    @error = false

    segment_config_service = AppServices::SegmentConfigurationService.new({scc_params: {
        type: @type, logger: logger}})

    if segment_fields_params[:reason_code] == "openitem"
      dynamic_segment_table = DynamicSegmentTable.all.order(:segment_number)

      segment_fields_config = segment_config_service.get_dynamic_field_configuration(dynamic_segment_table, @connector_instance)

      if segment_fields_config.nil?
        @error = segment_config_service.get_error
        @error_message = segment_config_service.get_error_message
      end

    else

      scc_segment_table = SccSegmentTable.select(['segment_number', 'field_number', 'field_name']).
          where(SccSegmentTable.arel_table[:field_name].does_not_match('Placeholder%')).all.order(:segment_number)

      segment_fields_config = segment_config_service.get_segment_field_configuration(scc_segment_table)
    end

    @errormessage = segment_config_service.get_error_message
    @error = segment_config_service.get_error

    if @error == true and @errormessage.blank? and segment_fields_config.include? "401"
      @errormessage = "An authorisation error to S4/Hana has been occurred"
    end

    if @error == true
      respond_to do |format|
        format.json { render :json => {"success": false, "message": @errormessage}, status: :unprocessable_entity }
      end
    else
      respond_to do |format|
        format.json { render json: segment_fields_config.html_safe, status: :ok }
      end

    end
  end


  def update

    segment_fields = params.to_json

    segment_config_service = AppServices::SegmentConfigurationService.new({scc_params: {
        type: @type, logger: logger}})

    if segment_fields_params[:reason_code] == "openitem"
      dynamic_segment_table = DynamicSegmentTable.all.order(:segment_number)
      if dynamic_segment_table.empty?
        total_status = segment_config_service.save_dynamic_field_configuration(segment_fields, dynamic_segment_table)
      else
        total_status = segment_config_service.update_dynamic_field_configuration(segment_fields, dynamic_segment_table)
      end
    else

      scc_segment_table = SccSegmentTable.all.order(:segment_number)
      if scc_segment_table.empty?
        total_status = segment_config_service.save_segment_field_configuration(segment_fields, scc_segment_table)
      else
        total_status = segment_config_service.update_segment_field_configuration(segment_fields, scc_segment_table)
      end

    end

    message = segment_config_service.get_message

    if total_status == true and not segment_fields_params[:reason_code] == "openitem"

      respond_to do |format|
        format.json { render :json => {"success": true, "message": "Updated, " + message, status: :ok} }
      end

    end


  end

  def segment_fields_params

    params.permit(:reason_code)

  end

end

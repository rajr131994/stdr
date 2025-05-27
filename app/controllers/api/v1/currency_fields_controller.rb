class Api::V1::CurrencyFieldsController < Api::V1::ApiBaseController


  def index

    connection_profile = ConnectionProfile.find_by(:default_connection_profile => true)
    erp_destination = Destination.find_by(:connection_profile_id => connection_profile.id, :destination_type => 1)

    extractor_type= params['integration_type']

    if connection_profile.nil?

      @error_message << "There is no default connection profile configured"
      @error = true
    elsif erp_destination.nil?

      @error_message << "There are no required S4H credentials found in the connection profile"
      @error = true
    end

    currency_field_service = AppServices::CurrencyFieldService.new({currency_params: {type: @type, logger: logger},
                                                                   gke_enabled: connection_profile.gke_enabled
                                                                   })
    currency_fields = currency_field_service.get_currency_fields(connection_profile, @connector_instance.blackline_instance_id.to_s, erp_destination, extractor_type)

    @error = currency_field_service.get_error
    @error_message = currency_field_service.get_error_message

    if @error == true

      respond_to do |format|
        format.json { render :json => {"success": false, "message": @error_message}, status: :unprocessable_entity }
      end

    else

      respond_to do |format|
        format.json { render json: currency_fields, status: :ok }
      end

    end

  end


end

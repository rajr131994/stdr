class Api::V1::BaseDateFieldsController < Api::V1::ApiBaseController


  def index

    base_date_fields = AppServices::BaseDateFieldService.new({base_date_params: {
        type: @type, logger: logger}
                                                            }).get_base_date_fields
    respond_to do |format|
      format.json { render json:  base_date_fields, status: :ok }
    end

  end


end

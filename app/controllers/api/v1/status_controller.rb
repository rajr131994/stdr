class Api::V1::StatusController < Api::V1::ApiBaseController

  before_action :set_extract_run_object, only: [:get, :update, :destroy]

  def show
    respond_to do |format|
      format.json { render :index, status: :ok }
    end
  end

  def update

    tenant = Apartment::Tenant.current

    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})

    @update = false
    @error = false

    if extract_run_params[:status] != 4 and extract_run_params[:status] != 7
      @logger_service.log_message('error', "StatusController",
                                  "Status controller - tenant: #{tenant} ERROR - Status code not allowed, should be 4 or 7, not updated for extract run : #{params[:id]}")
      message = "tenant: #{tenant} ERROR - Status code not allowed, should be 4 or 7, not updated for extract run : #{params[:id]}"
      @error = true
    end

    if @error == false
      @update = @extract_run.update_attribute(:status, extract_run_params[:status])
    end

    if @update == false and @error == false

      @logger_service.log_message('error', "StatusController",
                                  "Status controller - tenant: #{tenant} UNKNOWN ERROR - Status is not updated for extract run : #{params[:id]}")

      message = "tenant: #{tenant} UNKNOWN ERROR - Status is not updated for extract run : #{params[:id]}"
    end

    respond_to do |format|
      if @update == true and @error == false
        format.json { render :json => {"success": true, "message": "Updated"} }
      else
        format.json { render :json => {"success": false, "message": "Not updated : #{message}"}, status: 422 }
      end
    end
  end

  def set_extract_run_object

    @extract_run = ExtractRun.find(params[:id])
  end

  private

  #Never trust parameters from the scary internet, only allow the list through
  def extract_run_params
    params.require(:integration).permit(:status)
  end


end
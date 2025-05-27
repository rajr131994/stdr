class Api::V1::ExtractRunLogsController < Api::V1::ApiBaseController


  before_action :set_extract_run_object

  def show
    prepared_json = @extract_run.to_json(only: [:id, :job_log_message]
    )
    respond_to do |format|
      format.json { render json: prepared_json.html_safe }
    end

  end

  def set_extract_run_object

    @extract_run = ExtractRun.find(params[:id])
  end

  def extractrun_params

    params.permit( :id )

  end


end

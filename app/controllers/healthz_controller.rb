class HealthzController < HealthCheck::HealthCheckController
  def index
    errors = HealthCheck::Utils.process_checks(HealthCheck.standard_checks)
    response_status = 200
    unless errors.blank?
      msg = HealthCheck.include_error_in_response_body ? "#{HealthCheck.failure}: #{errors}" : HealthCheck.failure
      response_status = HealthCheck.http_status_for_error_object
      puts "health check failed with #{msg}"
    end
    response = Healthz.new(msg)

    respond_to do |format|
      format.json { render json: response, status: response_status}
    end
  end
end

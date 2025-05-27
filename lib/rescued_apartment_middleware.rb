module RescuedApartmentMiddleware
  def call(*args)
    begin
      super
    rescue Apartment::TenantNotFound
      Rails.logger.error "ERROR: Tenant not found"
      return [404, {"Content-Type" => "application/json"}, ["{\"success\": false, \"message\": \"Tenant not found\"}"] ]
    rescue ActiveRecord::RecordNotFound => ex
      #Rails.logger.error ex.message
      return [404, {"Content-Type" => "application/json"}, ["{\"success\": false, \"message\": \"#{ex.message}\"}"] ]
    rescue ActiveRecord::StatementInvalid => ex
      #Rails.logger.error ex.message
      return [405, {"Content-Type" => "application/json"}, ["{\"success\": false, \"message\": \"#{ex.message}\"}"] ]
    rescue ActiveRecord::Rollback=> ex
      #Rails.logger.error ex.message
      return [405, {"Content-Type" => "application/json"}, ["{\"success\": false, \"message\": \"#{ex.message}\"}"] ]
    rescue ActionController::ParameterMissing=> ex
      #Rails.logger.error ex.message
      return [400, {"Content-Type" => "application/json"}, ["{\"success\": false, \"message\": \"#{ex.message}\"}"] ]
    end
  end
end

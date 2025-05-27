class ApplicationController < ActionController::Base
  protect_from_forgery unless: -> { request.format.json? }
  before_action :cors_set_access_control_headers
  before_action :set_connector_instance
  before_action :set_scope
  before_action :set_cache_headers

  def version
    render json: { service: populate_service_info }
  end

  def populate_service_info
    {
      name: SERVICE_NAME,
      type: SERVICE_TYPE,
      version: VERSION
    }
  end

  protected

  def set_connector_instance
    @connector_instance = Apartment::Tenant.current == 'public' ? '' : ConnectorInstance.find(::Apartment::Tenant.current)
  end

  def set_scope
    $scope = request.headers['Scope']
  end

  private

  def set_cache_headers
    response.headers["Cache-Control"] = "no-store, no-cache"
  end

  def cors_set_access_control_headers
    #headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST, PUT, DELETE, GET, PATCH, OPTIONS'
    headers['Access-Control-Request-Method'] = '*'
    headers['Access-Control-Allow-Headers'] = 'Origin, X-Requested-With, Content-Type, Accept, Authorization'
  end

end

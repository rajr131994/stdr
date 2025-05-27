class Api::V1::ConnectorInstancesController < Api::V1::ApiBaseController
  #before_action :authenticate_api_with_scope, unless: -> { ENV['RAILS_ENV'].to_s == 'development' }
  skip_before_action :authenticate_api
  skip_before_action :set_connector_instance

  #Works with Link. Automatic

  def create
    ConnectorInstance.transaction do
      # Check in SCP if subaccount exists for customer. If not raise an Exception.
      @connector_instance = ConnectorInstance.new({:id => ci_params[:id], :blackline_instance_id => instance_params["bl_instance_id"],
                                                   :connector_instance_params => ci_params[:connector_instance_params]})
      respond_to do |format|
        if @connector_instance.save

          #TODO refactor seed file
          Apartment::Tenant.switch!(@connector_instance.id)

          format.json {render :json => {"success": true, "message": "Created", "connector_instance": @connector_instance.to_json}}
        else
          format.json {render :json => {"success": false, "message": "Tenant not created. Errors: #{@connector_instance.errors.full_messages.join(',')}"}, status: :conflict}
        end
      end
    end
  end

  def destroy
    connector_instance = ConnectorInstance.find(params[:id])
    connector_instance.destroy!
    respond_to do |format|
      format.json {render :json => {"success": true, "message": "Destroyed"}}
    end
  end

  def authenticate_api_with_scope
    authenticate_api(ENV['STS_BLLINKTOCONNECTOR_SCOPE'])
  end

  def ci_params
    params.require(:connector_instance).permit(:id, connector_instance_params: {})
  end

  def instance_params
    params.require(:instance)
          .permit(:id, :bl_instance_id)
  end
end

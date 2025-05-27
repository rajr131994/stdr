class Api::V1::SegmentConfigurationsController < Api::V1::ApiBaseController

  before_action :set_type, only: [:show]

  def show

    definition_description = AppServices::IntegrationService.new({ integration_params: {
        type:   @type, logger: logger  }
                                                                            }).get_definition_description
    scc_service = AppServices::SegmentConfigurationService.new({ scc_params: {
        type:   @type, logger: logger  }
                                                               })
    placeholder_label = scc_service.get_placeholder_label

    definition = Definition.where(:definition_description => definition_description)
    if definition.nil?
      @logger_service.log_message('error', "SegmentConfigurationsController",
                                  "SegmentConfigurationsController - show -  Definition not present with description : #{definition_description}")
      raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type not found"
    end

    def_lines = DefLine.where(:definition => definition)
    if def_lines.nil?
      @logger_service.log_message('error', "SegmentConfigurationsController",
                                  "SegmentConfigurationsController - show -  Definition records not present with description : #{definition_description}")
      raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type not found"
    end

    scc_segment_table = SccSegmentTable.
        where(SccSegmentTable.arel_table[:field_name].does_not_match(placeholder_label + '%')).all.order(:segment_number)


    segment_combination_json = scc_service.get_segment_configuration(def_lines,scc_segment_table )


    respond_to do |format|
      format.json { render json: segment_combination_json, status: :ok }
    end
  end


  def set_type

    @type = params[:id].to_i

  end

  def segment_configurations_params

    params.permit(:id)

  end


end

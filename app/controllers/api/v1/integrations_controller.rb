class Api::V1::IntegrationsController < Api::V1::ApiBaseController
  #before_action :authenticate_api_with_scope, unless: -> { ENV['RAILS_ENV'].to_s == 'development' }
  #skip_before_action :authenticate_api
  before_action :set_schedule_object, only: [:show, :update, :destroy]

# TODO Exchange rates implement
# TODO Transactions
# TODO validation test input fields error handling
# TODO RUN once
# TODO UTC time storage
# TODO retry CRON

#Integration controller
  def index
    @schedules = Schedule.all.order(:id)

    @schedules.each do |schedule|
      if schedule.template_id == 11
        schedule.template_id = 10
        schedule.output_target = 2
      elsif schedule.template_id == 10
        schedule.output_target = 1
      end
    end
    respond_to do |format|
      format.json { render json: @schedules.to_json(methods: [:output_target],
                                                    include: {schedule_lines: {},
                                                    connection_profile: {:except => [:client_secret_dest, :client_secret_extract, :password,
                                                                                               :encrypted_password, :encrypted_password_iv, :encrypted_client_secret_extract,
                                                                                               :encrypted_client_secret_extract_iv, :encrypted_client_secret_dest, :encrypted_client_secret_dest_iv]}}) }
    end
  end

  def show
    prepared_json = @schedule.to_json(include: {schedule_lines: {},
                                                connection_profile: {:except => [:client_secret_dest, :client_secret_extract, :password,
                                                                                 :encrypted_password, :encrypted_password_iv, :encrypted_client_secret_extract,
                                                                                 :encrypted_client_secret_extract_iv, :encrypted_client_secret_dest, :encrypted_client_secret_dest_iv]}})
    respond_to do |format|
      format.json { render json: prepared_json.html_safe }
    end
  end

  def create

    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})

    tenant = Apartment::Tenant.current

    # @restextractor need not be initialized here, so does connection_profile - review it
    connection_profile = ConnectionProfile.find_by_id(schedule_params[:connection_profile_id])
    # Client for SCP Api
    @restextractor = connection_profile.gke_enabled ? ExtractorService.new(@logger_service, tenant)
                                                    : RestscpData.new(@logger_service, tenant)


    # Check if required fields are present, ExtractData is the virtual model
    @extractdata = ExtractData.new(schedule_params)
    if @extractdata.valid?

      integration_service = AppServices::IntegrationService.new({integration_params: {
          type: @extractdata.type, logger: logger, extract_data: @extractdata, rest_extractor: @restextractor}})

      definition_description = integration_service.get_definition_description

      #Get definition
      definition = Definition.find_by(:definition_description => definition_description)
      if definition.nil?
        #logger.error "Extractruns - create -  Definition not present Definition : #{definition_description}"
        @logger_service.log_message('error', "Integrations",
                                    "Integrations - create -  Tenant : #{tenant} Definition not present Definition : #{definition_description}")
        raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type Definition not found"

      end

      #Get template by id
      if @extractdata.type == 7
        template = Template.find_by(:definition_id => definition.id, :template_description => "GetAccountBalanceAnalysis")
      else
        template = Template.find_by(:definition_id => definition.id)
      end
      if template.nil?

        @logger_service.log_message('error', "Integrations",
                                    "Integrations - create -  Tenant : #{tenant} Integration controller -  Error with create integration, Extractor type not present: #{@extractdata.type}")
        raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type Template not found"

      end

      #Get deftype
      def_type = Deftype.find(definition.deftype_id)
      if def_type.nil?

        @logger_service.log_message('error', "Integrations",
                                    "Integrations - create -  Tenant : #{tenant} Error with create integration, Definition type not found: #{definition.deftype_id}")
        raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type Definition type not found"

      end

      if schedule_params[:runname].nil?

        @logger_service.log_message('error', "Integrations",
                                    "Integrations - create -  Tenant : #{tenant} Error Runname is not supplied")
        raise ActiveRecord::StatementInvalid, "Name is not supplied"

      end

      if schedule_params[:testrun] == true

        @logger_service.log_message('error', "Integrations",
                                    "Integrations - create -  Tenant : #{tenant} Error Testrun is true")
        raise ActiveRecord::StatementInvalid, "Testrun can't be true"

      end

      #Get destinations by type and connection profile id
      # Data ingestion API is leading
      destination = Destination.find_by(:connection_profile_id => @extractdata.connection_profile_id, :destination_type => @extractdata.erp_destination_type)
      if destination.nil?

        @logger_service.log_message('error', "Integrations",
                                    "Integrations - create -  Tenant : #{tenant} Error Destination S4H is not found in connection profile : #{@extractdata.connection_profile_id}")
        raise ActiveRecord::StatementInvalid, "Destination S4H not found in selected connection profile"

      end

      destination_ftp = Destination.find_by(:connection_profile_id => @extractdata.connection_profile_id, :destination_type => @extractdata.ftp_destination_type)

      if destination_ftp.nil? and @extractdata.type == 1

        @logger_service.log_message('error', "Integrations",
                                    "Integrations - create -  Tenant : #{tenant} Error Destination FTP is not found in connection profile : #{@extractdata.connection_profile_id}")
        raise ActiveRecord::StatementInvalid, "Destination FTP not found in selected connection profile, required for ExchangeRates extractor"
      end

      if destination_ftp.nil?
        destination_iapi = Destination.find_by(:connection_profile_id => @extractdata.connection_profile_id, :destination_type => @extractdata.api_destination_type)
        if destination_iapi.nil?

          @logger_service.log_message('error', "Integrations",
                                      "Integrations - create -  Tenant : #{tenant} Error Destination IAPI is not found in selected connection profile : #{@extractdata.connection_profile_id}")
          raise ActiveRecord::StatementInvalid, "Destination FTP or IAPI not found in connection profile"

        end
      end

      integration_id = integration_service.save_integration(template, definition, def_type, destination, definition_description, @connector_instance.blackline_instance_id.to_s, logger)

      respond_to do |format|
        format.json { render json: {"success": true, "message": "Integration is created", "integrationId": integration_id}, status: :ok }
      end

    else

      respond_to do |format|
        format.json { render json: {"success": false, "message": @extractdata.errors.messages}, status: :unprocessable_entity }
      end

    end

  end

  def destroy

    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})
    tenant = Apartment::Tenant.current


    integration_service = AppServices::IntegrationService.new({integration_params: {
        type: nil, logger: logger, extract_data: @extractdata, rest_extractor: @restextractor}})

    if params[:id].split(',').length() > 1 and (ENV["SCP_ENV_TYPE"].upcase == 'DEV' or ENV["SCP_ENV_TYPE"].upcase == 'TST')
      success = integration_service.delete_integrations(params[:id].split(','))

    elsif params[:id].to_i == 0 and (ENV["SCP_ENV_TYPE"].upcase == 'DEV' or ENV["SCP_ENV_TYPE"].upcase == 'TST')

      schedule_array = []
      schedule_array << params[:id]
      success = integration_service.delete_integrations(schedule_array)

    else
      #Get template

        template = Template.find_by(:id => @schedule.template_id)

      if template.nil?

        @logger_service.log_message('error', "Integrations",
                                    "Integration controller -  tenant: #{tenant} Error with create integration, template not present: #{@schedule.template_id}")
        raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type Template not found"
      else

        @logger_service.log_message('info', "Integrations",
                                    "Integration controller - tenant: #{tenant} template found : #{@schedule.template_id}")
      end

      #Get definition
      definition = Definition.find(template.definition_id)
      if definition.nil?

        @logger_service.log_message('error', "Integrations",
                                    "tenant: #{tenant} Error with delete integration, definition not present in tenant: #{Apartment::Tenant.current}")
        raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type Definition not found"
      end

      #Get deftype
      def_type = Deftype.find(definition.deftype_id)
      if template.nil?

        @logger_service.log_message('error', "Integrations",
                                    "tenant: #{tenant} Error with delete integration, Template not present in tenant: #{Apartment::Tenant.current}")
        raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type Definition type not found"
      end

      success = integration_service.delete_integration(template, definition, def_type, @schedule)

      if not success

        @logger_service.log_message('error', "Integrations",
                                    "tenant: #{tenant} Error with delete integration, Extract history records are present for integration")
        @schedule.update_attribute(:cron_text, "Disabled")

        respond_to do |format|
          format.json { render json: {"success": false, "message": "Integration not deleted but disabled, this can be because of : an active integration or that there extract history runs present which are planned or running and not older then 4 hours"}, status: :ok }
        end
      end

    end

    if success
      respond_to do |format|
        format.json { render json: {"success": true, "message": "Integration(s) has been deleted"}, status: :ok }
      end
    end
  end

  def update

    tenant = Apartment::Tenant.current

    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})

    # @restextractor need not be initialized here, so does connection_profile - review it
    connection_profile = ConnectionProfile.find_by_id(schedule_params[:connection_profile_id])
    # Client for SCP Api
    @restextractor = connection_profile.gke_enabled ? ExtractorService.new(@logger_service, tenant)
                                                    : RestscpData.new(@logger_service, tenant)

    # put action
    @extractdata = ExtractData.new(schedule_params)

    if not schedule_params[:runname].nil?
      raise ActiveRecord::StatementInvalid, "Name can't be changed"
    end

    if schedule_params[:testrun] == true
      raise ActiveRecord::StatementInvalid, "Testrun can't be true"
    end

    if @extractdata.valid?

      integration_service = AppServices::IntegrationService.new({integration_params: {
          type: @extractdata.type, logger: logger, extract_data: @extractdata, rest_extractor: @restextractor}})

      definition_description = integration_service.get_definition_description


      #Get definition
      definition = Definition.find_by(:definition_description => definition_description)
      if definition.nil?

        @logger_service.log_message('error', "Integrations",
                                    "Extractruns - create -  Definition not present Definition : #{definition_description}")
        raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type Definition not found"

      end

      #Get template by id
      if @extractdata.type == 7
        template = Template.find_by(:definition_id => definition.id,:template_description => "GetAccountBalanceAnalysis")
      else
        template = Template.find_by(:definition_id => definition.id)
      end
      if template.nil?

        @logger_service.log_message('error', "Integrations",
                                    "Extractruns - create -  Definition present in Definition : #{definition.deftype_id}")
        raise ActiveRecord::RecordNotFound, "Error with configuration - Extractor type Template not found"

      else
        template.file_name_extension = @extractdata.file_extension

      end


      #Get deftype
      def_type = Deftype.find(definition.deftype_id)
      if def_type.nil?

        @logger_service.log_message('error', "Integrations",
                                    "Extractruns - create -  Definition present in Definition : #{definition.deftype_id}")
        raise ActiveRecord::StatementInvalid, "Error with configuration - Extractor type Definition type not found"
      end

      if @extractdata.run_once.nil?
        @extractdata.run_once = false
      end

      #Get destinations by type and connection profile id
      # Data ingestion API is leading
      erp_destination = Destination.find_by(:connection_profile_id => @extractdata.connection_profile_id, :destination_type => @extractdata.erp_destination_type)
      if erp_destination.nil?

        @logger_service.log_message('error', "Integrations",
                                    "Extractruns - create -  Definition present in Definition : #{definition.deftype_id}")
        raise ActiveRecord::StatementInvalid, "Destination S4H not found in connection profile"

      end

      extract_run_id = nil
      if not @extractdata.run_once

        integration_service.update_integration(template, definition, def_type, erp_destination, definition_description, @schedule, @connector_instance.blackline_instance_id.to_s, logger)
        message = "Integration is Updated"
      else

        file_destination_db = Destination.find_by(:connection_profile_id => @extractdata.connection_profile_id, :destination_type => @extractdata.ftp_destination_type)

        extract_run_id = integration_service.run_once_integration(def_type, @schedule, logger, template, erp_destination, file_destination_db, definition, @connector_instance.blackline_instance_id.to_s)
        message = "Integration Run once scheduled"
      end

      respond_to do |format|
        resp_json = {"success": true, "message": message }

        unless extract_run_id.nil?
          resp_json["extract_run_id"] = extract_run_id
        end

        format.json { render json: resp_json , status: :ok }
      end

    else

      respond_to do |format|
        format.json { render json: {"success": false, "message": @extractdata.errors.messages}, status: :unprocessable_entity }

      end
    end
  end

  def set_schedule_object

    if params[:id].to_i != 0

      @schedule = Schedule.find(params[:id])

    end

  end

  private



#Never trust parameters from the scary internet, only allow the list through
  def schedule_params

    #params check . The attributes below will be saved in the database
    return params.require(:integration).permit(:type, :runname, :periodtype, :ledger, :companycode, :glaccount, :exchangeratetype, :leadingcurrency, :followingcurrency, :exchangeRateFrom, :keydate, :language, :zeroBalanceIncluded, :blockedAccountsIncluded, :excludeSpecialPeriods, :currentPeriodIncluded, :schedule, :retrySchedule, :maxRetry, :testrun, :connection_profile_id, :segment_configuration_json,
                                               :posting_date_from, :posting_date_to, :document_type_from, :document_type_to, :fiscal_year_from, :fiscal_year_to, :ledgerVersion, { cnsldtUnit: [{inclusion: [], exclusion: []}]}, { fsItem: [{inclusion: [], exclusion: []}]}, { postingLevel: [{inclusion: [], exclusion: []}]}, { documentType: [{inclusion: [], exclusion: []}]}, :dimension, :cnsldtCOA, :fiscalYearVariant, :recordType, :subItem, :output_target, :file_name, :txn_file_name, :cnsldtFSHierarchy, :cnsldtVersion, :validityDate,
                                               :account_type_from, :account_type_to, :entry_date_from, :entry_date_to, :clearing_date_from, :clearing_date_to,
                                               :document_status_from, :document_status_to, :document_number_from, :document_number_to, :gl_account_currency, :gl_reporting_currency, :gl_alternate_currency,
                                               :periodType, :customer_open_items, :gl_open_items,
                                               :vendor_open_items, :run_once, :document_type, :account_type, :document_type, :customer, :supplier, :document_status, :clearing_offset, :base_date_1, :base_date_2, :base_date_3, :base_date_4, :schedulerDisabled, :output_format, :output_format_acc, :file_extension, :file_extension_acc)


  end


end
class Api::V1::ExtractrunsController < Api::V1::ApiBaseController

  #before_action :authenticate_api, unless: -> { ENV['RAILS_ENV'].to_s == 'development' }
  #skip_before_action :authenticate_api
  before_action :set_extractrun_object, only: [:show, :update, :destroy]

  def index

    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})

    date_from = params[:date_from]
    date_to = params[:date_to]

      if not date_from.nil?
        date_from_ts_start = Date.parse(date_from).to_datetime - 1.seconds
        date_from_ts_end = Date.parse(date_from).to_datetime + 1.days


      end
      if not date_to.nil?
        date_from_ts_end = Date.parse(date_to).to_datetime + 1.days


      end


      if not date_from.nil? and date_to.nil?

        created_at = ExtractRun.arel_table[:created_at]
        @extract_runs = ExtractRun.where(created_at.gt(date_from_ts_start)).where(created_at.lt(date_from_ts_end)).order(:id).as_json(:except => :job_log_message)
      elsif not date_from.nil? and not date_to.nil?
        created_at = ExtractRun.arel_table[:created_at]

        @extract_runs = ExtractRun.where(created_at.gt(date_from_ts_start)).where(created_at.lt(date_from_ts_end)).order(:id).as_json(:except => :job_log_message)

      else
        @extract_runs = ExtractRun.all.order(:id)
      end

      prepared_json = @extract_runs.to_json(:except => [:job_log_message], include: {
        schedule: {connection_profile: {:except => [:client_secret, :client_secret_extract, :password,
                                                    :encrypted_password, :encrypted_password_iv, :encrypted_client_secret_extract,
                                                    :encrypted_client_secret_extract_iv, :encrypted_client_secret_dest, :encrypted_client_secret_dest_iv,
                                                    :client_secret_dest]}}
      })
      respond_to do |format|
        format.json { render json: prepared_json.html_safe }
      end

    end

    def show


      @extract_run = ExtractRun.find(params[:id])

      prepared_json = @extract_run.to_json( :except => [ :job_log_message ],include: {
        schedule: { connection_profile: { :except => [:client_secret, :client_secret_extract, :password,
                                                      :encrypted_password, :encrypted_password_iv, :encrypted_client_secret_extract,
                                                      :encrypted_client_secret_extract_iv, :encrypted_client_secret_dest, :encrypted_client_secret_dest_iv,
                                                      :client_secret_dest ] } }
      })

      respond_to do |format|
        format.json { render json: prepared_json.html_safe }
      end
    end

    def create

      @error = false
      @errormessage = []

      tenant = Apartment::Tenant.current
      @logger_service = AppServices::LoggerService.new({log_params: {
          logger: logger}})

      @connection_profile = ConnectionProfile.find_by_id(extractrun_params[:connection_profile_id])
      if @connection_profile.nil?

        @logger_service.log_message('error', "ExtractRuns", "Connection profile not found")
        raise ActiveRecord::RecordNotFound, "Connection profile not found"
      end

      # Client for SCP Api
      @restextractor = @connection_profile.gke_enabled ? ExtractorService.new(@logger_service, tenant)
                                                        : RestscpData.new(@logger_service, tenant)

      if extractrun_params[:testrun] == false

        @logger_service.log_message('error', "ExtractRuns",
                                    "Testrun can't be false")
        raise ActiveRecord::StatementInvalid, "Testrun can't be false"
      end

      # Check if required fields are present, ExtractData is the virtual model
      @extractdata = ExtractData.new(extractrun_params)
      
      if @extractdata.type.nil?

        @logger_service.log_message('error', "ExtractRuns",
                                    "Extractor type is not supplied")
        raise ActiveRecord::StatementInvalid, "Extractor type is not supplied"
      end

      if @extractdata.valid?

        integration_service = AppServices::IntegrationService.new({ integration_params: {
            type: @extractdata.type, logger: logger, extract_data: @extractdata, rest_extractor: @restextractor  }
                                                                  })
        definition_description = integration_service.get_definition_description

        #Get definition
        definition = Definition.find_by(:definition_description => definition_description)
        if definition.nil?
          @logger_service.log_message('error', "ExtractRuns",
                                      "Definition not present Definition : #{definition_description}")
          raise ActiveRecord::RecordNotFound, "Error with configuration - Definition not found #{definition_description}"
        end

        if @extractdata.type == 7
          template = Template.find_by(:definition_id => definition.id,:template_description => "GetAccountBalanceAnalysis")
        else
          template = Template.find_by(:definition_id => definition.id)
        end

        if template.nil?
          @logger_service.log_message('error', "ExtractRuns",
                                      "Error with configuration - Template not found with definition id: #{definition.id}")
          raise ActiveRecord::RecordNotFound, "Error with configuration - Template not found with definition id: #{definition.id}"
        else
          template.file_name_extension = @extractdata.file_extension
        end


        #create schedule record
        @logger_service.log_message('info', "ExtractRuns",
                                    "create - ExtractData model is valid")


        #Get destination id
        erp_destination = Destination.find_by(:connection_profile_id => @extractdata.connection_profile_id, :destination_type => @extractdata.erp_destination_type)
        if erp_destination.nil?

          @logger_service.log_message('error', "ExtractRuns",
                                      "Destination S4H not found in connection profile #{@extractdata.connection_profile_id}")
          raise ActiveRecord::RecordNotFound, "Error with configuration - Destination S4H not found in connection profile"
        end

        #Get deftype
        deftype = Deftype.find(definition.deftype_id)
        if deftype.nil?

          @logger_service.log_message('error', "ExtractRuns",
                                      "Definition type not present in Definition type id: #{definition.deftype_id}")
          raise ActiveRecord::RecordNotFound, "Error with configuration with definition type of extractor type: #{@extractdata.type}"
        end

        extract_response = integration_service.get_validation_run(template,definition,deftype,erp_destination,definition_description,@connection_profile,@connector_instance.blackline_instance_id.to_s,logger)

        # update job log with DR logs
        if not extract_response.nil? || extract_response.body.nil? || extract_response.body.empty?
          json_message = extract_response.parsed_response
          secureErrorMessages(integration_service)
          @error = integration_service.get_error
        else
          @error = true

          secureErrorMessages(integration_service)
          @errormessage << "Validation service unavailable"
          @logger_service.log_message('error', "ExtractRuns",
                                      "Validation SCP service unavailable error no response")
        end

      else
        @error = true
        @logger_service.log_message('error', "ExtractRuns",
                                    "Error with validation: #{@extractdata.errors.messages}")
        @errormessage = @extractdata.errors.messages
      end

      if @error == true

        if @errormessage.nil?
          @errormessage << "Validation SCP service unavailable error no response"
        end

          respond_to do |format|
            format.json { render :json => {"success": false, "message": @errormessage}, status: :unprocessable_entity }
          end
      else
        respond_to do |format|
          format.json { render json: json_message, status: :ok }
        end

      end
    end

    def destroy

    end

    def update

    end

    def set_extractrun_object
      logger.info "Extractruns - Update or Delete - Find extractrun : #{params[:id]}".html_safe
      @extract_run = ExtractRun.find(params[:id])
    end

    private

  def secureErrorMessages(integration_service)
    if integration_service.get_error_message && integration_service.get_error_message.is_a?(Array)
      integration_service.get_error_message.each { |x| @errormessage << x.html_safe }
    elsif integration_service.get_error_message && integration_service.get_error_message.is_a?(String)
      @errormessage << integration_service.get_error_message.html_safe
    end
  end

  #Never trust parameters from the scary internet, only allow the list through
    def extractrun_params

      params.require(:integration).permit(:type, :runname, :periodtype, :ledger, :companycode, :glaccount, :leadingcurrency, :followingcurrency, :exchangeRateFrom, :keydate, :exchangeratetype, :language, :zeroBalanceIncluded, :blockedAccountsIncluded, :excludeSpecialPeriods, :currentPeriodIncluded, :schedule, :retrySchedule, :maxRetry, :testrun, :connection_profile_id, :segment_configuration_json,
                                          :posting_date_from, :posting_date_to, :document_type_from, :document_type_to, :fiscal_year_from, :fiscal_year_to, :ledgerVersion, { cnsldtUnit: [{inclusion: [], exclusion: []}]}, { fsItem: [{inclusion: [], exclusion: []}]}, { postingLevel: [{inclusion: [], exclusion: []}]}, { documentType: [{inclusion: [], exclusion: []}]}, :dimension, :cnsldtCOA, :fiscalYearVariant, :recordType, :subItem, :output_target, :file_name, :txn_file_name, :cnsldtFSHierarchy, :cnsldtVersion, :validityDate,
                                          :account_type_from, :account_type_to, :entry_date_from, :entry_date_to, :clearing_date_from, :clearing_date_to,
                                          :document_status_from, :document_status_to, :document_number_from, :document_number_to, :date_from, :date_to, :gl_account_currency, :gl_reporting_currency, :gl_alternate_currency,
                                          :periodType, :customer_open_items, :gl_open_items, :vendor_open_items, :account_type,:document_type,:customer,:supplier,:document_status, :clearing_offset, :base_date_1, :base_date_2, :base_date_3, :base_date_4, :output_format, :output_format_acc, :file_extension, :file_extension_acc)

    end

  end
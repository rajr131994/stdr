require_dependency "sts"
#require_dependency "link_engine/sts"
require_dependency "exceptions"
#require_dependency "link_engine/exceptions"

class Api::V1::ApiBaseController < ApplicationController

  around_action :catch_exceptions, unless: -> { ENV['RAILS_ENV'].to_s == 'development' }
  before_action :authenticate_api, unless: -> { ENV['RAILS_ENV'].to_s == 'development' || $scope == 'DataIngestionAPI' }

  before_action :authenticate_scp_api, unless: -> { ENV['RAILS_ENV'].to_s == 'development' || $scope != 'DataIngestionAPI' }

  private

  def authenticate_api (sts_scope = ENV['STS_BLLINK_SCOPE'])
    logger.info "*************** authenticate_api START *********************"
    sts_response = Sts.post(
        "#{ENV['STS_URL']}#{ENV['STS_INTROSPECT_ENDPOINT']}",
        headers: {
            "Accept" => "application/json",
            "Content-Type" => "application/x-www-form-urlencoded"
        },
        basic_auth: {
          username: sts_scope,
          password: ENV['STS_BLLINK_SCOPE_SECRET']
        },
        body: {
            "token" => request.headers['Authorization'].split(' ')[1],
            "client_id" => sts_scope
        }
    )
    if !sts_response.parsed_response['active']
      raise InvalidTokenError
    end
    logger.info "@connector_instance : #{@connector_instance.to_s}"
    # ConnectorInstance can be null for a few cases configured in apartment.rb
    # which does not require Connector-Instance http header
    unless @connector_instance.to_s.empty?
      # Only check if instances matche if using STS_BLLINK_SCOPE. Check is not needed for M2M (BLL -> CBE) scope
      logger.info "Compare blackline_instance_id from DB: #{@connector_instance.blackline_instance_id} >> STS #{sts_response.parsed_response['InstanceId']} AND is blank #{sts_response.parsed_response['InstanceId'].blank?}".html_safe
      if sts_scope === ENV['STS_BLLINK_SCOPE']
        if (sts_response.parsed_response['InstanceId'] != @connector_instance.blackline_instance_id.to_s) || (sts_response.parsed_response['InstanceId'].blank?)
          raise TokenInstanceMismatchError
        end
      end
    end
    if !sts_response.parsed_response.has_key?("active") && !sts_response.parsed_response.has_key?("scope")
      raise 'unknown response from STS service'
    end
    unless ENV['ACCEPTED_SCOPES'].split(',').include? sts_response.parsed_response['scope']
      raise InvalidScopeError
    end
    @sts_scope = sts_response.parsed_response['scope']
    @bl_instance_id = sts_response.parsed_response['InstanceId']
    logger.info "sts token introspect response : #{sts_response.body}"
    logger.info "*************** authenticate_api END *********************"
  end

  def authenticate_scp_api
    logger.info "*************** authenticate_scp_api START *********************"
    environment_upcase = ENV["SCP_ENV_TYPE"].upcase
    if environment_upcase.nil? || environment_upcase.empty?
      raise "Environment variable not present or empty: SCP_ENV_TYPE"
    end

    if ENV["BL_API_BASE_URL"].nil? || ENV["BL_API_BASE_URL"].empty?
      raise ActionController::ParameterMissing, "Environment variable BL_API_BASE_URL not present or empty"
    end
    if ENV["STS_INTROSPECT_ENDPOINT"].nil? || ENV["STS_INTROSPECT_ENDPOINT"].empty?
      raise ActionController::ParameterMissing, "Environment variable STS_INTROSPECT_ENDPOINT not present or empty"
    end
    if ENV["STS_SCOPE_NAME"].nil? || ENV["STS_SCOPE_NAME"].empty?
      raise ActionController::ParameterMissing, "Environment variable STS_SCOPE_NAME not present or empty"
    end
    if ENV["STS_SCOPE_SECRET"].nil? || ENV["STS_SCOPE_SECRET"].empty?
      raise ActionController::ParameterMissing, "Environment variable STS_SCOPE_SECRET not present or empty"
    end

    username = ENV["STS_SCOPE_NAME"]
    password = ENV["STS_SCOPE_SECRET"]

    sts_response = Sts.post(
        "#{ENV["STS_URL"]}#{ENV["STS_INTROSPECT_ENDPOINT"]}",
        headers: {
            "Accept" => "application/json",
            "Content-Type" => "application/x-www-form-urlencoded"
        },
        basic_auth: {:username => username, :password => password},
        body: {
            "token" => request.headers['Authorization'].split(' ')[1],
        }
    )

    if sts_response.nil?
      raise UnavailableError
    end

    if sts_response.code == 401
      raise InvalidTokenError
    end

    if sts_response.code != 200
      raise InvalidTokenError
    end

    if !sts_response.parsed_response['active']
     raise InvalidTokenError
    else
      sts_scope = sts_response.parsed_response['active']
    end

    # Only check if instances matche if using STS_BLLINK_SCOPE. Check is not needed for M2M (BLL -> CBE) scope
    # logger.info "Compare blackline_instance_id from DB: #{@connector_instance.blackline_instance_id} >> STS #{sts_response.parsed_response['InstanceId']} AND is blank #{sts_response.parsed_response['InstanceId'].blank?}"
    if sts_scope === ENV['STS_SCOPE_NAME']
      if (sts_response.parsed_response['InstanceId'] != @connector_instance.blackline_instance_id.to_s) || (sts_response.parsed_response['InstanceId'].blank?)
        raise InvalidScopeError
      end
    end

    if !sts_response.parsed_response.has_key?("active") && !sts_response.parsed_response.has_key?("scope")
      raise InvalidScopeError
    end
    logger.info "*************** authenticate_scp_api END *********************"
  end

  def catch_exceptions
    yield

  rescue InvalidTokenError => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'InvalidTokenError from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "Unauthorized:  #{ex.message}"}, status: :unauthorized}
    end
  rescue UnavailableError => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': "Host #{ENV["STS_URL"]} is unavailable from api base controller: " + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "STS host is unavailable:  #{ex.message}"}, status: :service_unavailable}
    end
  rescue InvalidScopeError => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'InvalidScopeError from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "Unauthorized:  #{ex.message}"}, status: :unauthorized}
    end
  rescue ActiveRecord::StatementInvalid => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'ActiveRecord::StatementInvalid from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "Invalid Statement:  #{ex.message}"}, status: :unprocessable_entity}
    end
  rescue ActiveRecord::RecordNotFound => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'ActiveRecord::RecordNotFound from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "Record not found: #{ex.message}"}, status: :not_found}
    end
  rescue ActionController::ParameterMissing => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'ActionController::ParameterMissing from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "Parameters Missing: #{ex.message}"}, status: :bad_request}
    end
  rescue ActionController::UnpermittedParameters => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'UnpermittedParameters from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "Unpermitted Parameters: #{ex.message}"}, status: :bad_request}
    end
  rescue ActiveModel::ForbiddenAttributesError => ex

    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'ForbiddenAttributesError from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "Forbidden Attributes: #{ex.message}"}, status: :bad_request}
    end
  rescue ActiveRecord::RecordInvalid => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'RecordInvalid from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "#{ex.message}"}, status: :bad_request}
    end
  rescue Apartment::TenantNotFound => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'TenantNotFound from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "tenant not found: #{ex.message}"}, status: :not_found}
    end
  rescue ActiveRecord::RecordNotUnique => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'RecordNotUnique from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "RecordNotUnique: #{ex.message}"}, status: :not_found}
    end
  rescue ActiveRecord::InvalidForeignKey => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'Extract history runs exist for integration id from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "InvalidForeignKey: #{ex.message}"}, status: :not_found}
    end
  rescue ActiveRecord::Rollback => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'Extract history runs exist for integration id from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "Rollback: #{ex.message}"}, status: :internal_server_error}
    end
  rescue => ex
    # Logging backtrace and message
    stacktrace_json ={'stacktrace': ex.backtrace, 'message': 'InvalidTokenError from api base controller: ' + ex.message}
    logger.error stacktrace_json.to_json
    respond_to do |format|
      format.json {render json: {"success" => false, :message => "Internal server error"}, status: :internal_server_error}
    end
  end

end
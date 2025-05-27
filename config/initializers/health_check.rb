class CustomHealthCheck

  require 'open3'

  def self.resque_scheduler_check

    unless Rails.env.production?
      check_result = true

    else

      stdout, stderr, status = Open3.capture3("ps aux | grep resque")

      check_result = stdout.include? "resque-pool-master[services.connectors.sap]: managing"

      if check_result == false
        check_result = stdout.include? "Schedules Loaded"
      end
    end

    return check_result ? "" : "Resque scheduler service is not running"

  end


  def self.btp_extractor_check
    # Set logger
    logger = Rails.logger

    @logger_service = AppServices::LoggerService.new({log_params: {
        logger: logger}})

    @restextractor = RestscpData.new(@logger_service, tenant)

    error =  @restextractor.check_btp_service
    message = @restextractor.get_error_message

    check_result = !error

    return check_result ? "" : "extractor service is not running : #{message}"


  end

end

SERVICE_NAME = 'services.connectors.s4hana_public_cloud'
SERVICE_TYPE = 'SAP Connector service'

# this is a replica of RedisHealthCheck class from health_check gem which accepts url and password.
# However, after image factory migration redis url itself will have the auth token and no password is required.
# But existing RedisHealthCheck is failing with an error "redis - ERR invalid password".
# So, added this custom health check to make it work for the new redis url
class RedisHealthCheck
  class << self
    def check
      raise "Wrong configuration. Missing 'redis' gem" unless defined?(::Redis)

      client.ping == 'PONG' ? '' : "Redis.ping returned #{res.inspect} instead of PONG"
    rescue Exception => err
      "redis - #{err.message}"
    ensure
      client.close if client.connected?
    end

    def client
      @client ||= Redis.new(url: HealthCheck.redis_url)
    end
  end
end


HealthCheck.setup do |config|

  # uri prefix (no leading slash)
  config.uri = 'health_check'

  # Text output upon success
  config.success = 'success'

  # Text output upon failure
  #config.failure = 'health_check failed'

  # Disable the error message to prevent /health_check from leaking
  # sensitive information
  config.include_error_in_response_body = true

  # Log level (success or failure message with error details is sent to rails log unless this is set to nil)
  #config.log_level = 'info'

  # Timeout in seconds used when checking smtp server
  config.smtp_timeout = 30.0

  # http status code used when plain text error message is output
  # Set to 200 if you want your want to distinguish between partial (text does not include success) and
  # total failure of rails application (http status of 500 etc)

  config.http_status_for_error_text = 200

  # http status code used when an error object is output (json or xml)
  # Set to 200 if you want to distinguish between partial (healthy property == false) and
  # total failure of rails application (http status of 500 etc)

  config.http_status_for_error_object = 200

  # bucket names to test connectivity - required only if s3 check used, access permissions can be mixed
  config.buckets = {'bucket_name' => [:R, :W, :D]}

  # You can customize which checks happen on a standard health check, eg to set an explicit list use:
  config.standard_checks = ['database', 'migrations', 'custom']

  # Or to exclude one check:
  config.standard_checks -= ['emailconf']

  # You can set what tests are run with the 'full' or 'all' parameter
  config.full_checks = ['database', 'migrations', 'custom', 'cache', 'redis', 'resque-redis', 'sidekiq-redis', 's3']

  # Add one or more custom checks that return a blank string if ok, or an error message if there is an error

  #config.add_custom_check do
  #  CustomHealthCheck.resque_scheduler_check # any code that returns blank on success and non blank string upon failure
  #end

  # Add another custom check with a name, so you can call just specific custom checks. This can also be run using
  # the standard 'custom' check.
  # You can define multiple tests under the same name - they will be run one after the other.

  #config.add_custom_check('sometest') do
  #  CustomHealthCheck.btp_extractor_check # any code that returns blank on success and non blank string upon failure
  #end

  # max-age of response in seconds
  # cache-control is public when max_age > 1 and basic_auth_username is not set
  # You can force private without authentication for longer max_age by
  # setting basic_auth_username but not basic_auth_password
  config.max_age = 1

  # Protect health endpoints with basic auth
  # These default to nil and the endpoint is not protected
  #config.basic_auth_username = 'my_username'
  #config.basic_auth_password = 'my_password'

  # Whitelist requesting IPs by a list of IP and/or CIDR ranges, either IPv4 or IPv6 (uses IPAddr.include? method to check)
  # Defaults to blank which allows any IP
  #config.origin_ip_whitelist = %w(123.123.123.123 10.11.12.0/24 2400:cb00::/32)

  # Use ActionDispatch::Request's remote_ip method when behind a proxy to pick up the real remote IP for origin_ip_whitelist check
  # Otherwise uses Rack::Request's ip method (the default, and always used by Middleware), which is more susceptable to spoofing
  # See https://stackoverflow.com/questions/10997005/whats-the-difference-between-request-remote-ip-and-request-ip-in-rails
  #config.accept_proxied_requests = false

  # http status code used when the ip is not allowed for the request
  config.http_status_for_ip_whitelist_error = 403

  # rabbitmq
  #config.rabbitmq_config = {}

  redis_url = "redis://default:#{ENV['REDIS_SERVER_PASSWORD']}@#{ENV['REDIS_SERVER_HOSTS']}/#{ENV['REDIS_DATABASE_NUMBER'] || '4'}"

  # When redis url/password is non-standard
  config.redis_url = redis_url # default ENV['REDIS_URL']
  # Only included if set, as url can optionally include passwords as well
  #config.redis_password = ENV['REDIS_SERVER_PASSWORD'] # default ENV['REDIS_PASSWORD']
  config.add_custom_check do
    RedisHealthCheck.check
  end

  # Failure Hooks to do something more ...
  # checks lists the checks requested
  #config.on_failure do |checks, msg|
  # log msg somewhere
  #end

  #config.on_success do |checks|
  # flag that everything is well
  #end

end
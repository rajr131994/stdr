# NOTE(Marin): adding support for requests that come through a load balancer. request.ip will not return the true origin or the request
class Rack::Attack
  class Request < ::Rack::Request
    def remote_ip
      @remote_ip ||= (env['HTTP_CF_CONNECTING_IP'] || env['action_dispatch.remote_ip'] || ip).to_s
    end

    def allowed_ip?

      env_whitelist = ENV['IP_WHITELIST']

      allowed_ips = %w[127.0.0.1 ::1]

      env_whitelist.delete(' ')
        if env_whitelist.include?(',')
          env_ips = env_whitelist.split(",")

          env_ips.each do | env_ip |
            allowed_ips << env_ip
          end
        elsif not env_whitelist.empty?
          allowed_ips << env_whitelist
        end

      puts "allowed_ips: #{allowed_ips.inspect}"
      allowed_ips.include?(remote_ip)
    end
  end

  safelist('allow from localhost') do |req|
    puts "Allowed IP: #{req.allowed_ip?}"
    puts "IP address: #{req.ip}"
    req.allowed_ip?
  end
end


Rack::Attack.cache.prefix = "rack:attack"

Rack::Attack.throttle("max requests in a period by ip", limit: ENV['RATE_LIMIT'].to_i, period: ENV['RATE_LIMIT_PERIOD'].to_i) do |request|
  headers = Hash[*request.env.select {|k,_v| k.start_with? 'HTTP_'}
                      .collect {|k,v| [k.sub(/^HTTP_/, ''), v]}
                      .collect {|k,v| [k.split('_').collect(&:capitalize).join('-'), v]}
                      .sort
                      .flatten]

  request.remote_ip unless (
    # /api/v1/journals also does not expect Connector-Instance header, it is derived from auth token
  (headers["Connector-Instance"].blank? && !request.path.include?('/api/v1/connector_instances') && !request.path.include?('/api/v1/journals')) ||
      headers['Authorization'].blank? ||
      request.path == "/" ||
      request.path.include?('/etc/passwd') ||
      request.path.include?('wp-admin') ||
      request.path.include?('wp-login') ||
      request.path.include?('/health_check')
  )
end

Rack::Attack.throttle("max requests in a period by ip without auth or to root route", limit: ENV['BAD_REQUEST_RATE_LIMIT'].to_i, period: ENV['RATE_LIMIT_PERIOD'].to_i) do |request|
  headers = Hash[*request.env.select {|k,_v| k.start_with? 'HTTP_'}
                      .collect {|k,v| [k.sub(/^HTTP_/, ''), v]}
                      .collect {|k,v| [k.split('_').collect(&:capitalize).join('-'), v]}
                      .sort
                      .flatten]
  request.remote_ip if (
      # NOTE(Marin): leaving below with greater limit because Link does not use a connector instances when callign each connenctor
      # /api/v1/journals also does not expect Connector-Instance header, it is derived from auth token
  (headers["Connector-Instance"].blank? && !request.path.include?('/api/v1/connector_instances') && !request.path.include?('/api/v1/journals')) ||
      headers['Authorization'].blank? ||
      request.path == "/" ||
      request.path.include?('/etc/passwd') ||
      request.path.include?('wp-admin') ||
      request.path.include?('wp-login')
  ) && request.path.exclude?('/health_check')
end

Rack::Attack.throttle('limit requests per minute per connector instance', limit: ENV['RATE_LIMIT'].to_i, period: ENV['RATE_LIMIT_PERIOD'].to_i) do |req|
  headers = Hash[*req.env.select {|k,_v| k.start_with? 'HTTP_'}
                      .collect {|k,v| [k.sub(/^HTTP_/, ''), v]}
                      .collect {|k,v| [k.split('_').collect(&:capitalize).join('-'), v]}
                      .sort
                      .flatten]

  headers["Connector-Instance"]
end

Rack::Attack.throttle('max requests in a period for health checks', limit: 300, period: 60) do |request|
  request.remote_ip if request.path.include?('/health_check') && request.get?
end


# NOTE(Marin): Log blocked events
ActiveSupport::Notifications.subscribe('rack.attack') do |name, _start, _finish, _request_id, req|
  request = req[:request]
  headers = Hash[*request.env.select {|k,v| k.start_with? 'HTTP_'}
                      .collect {|k,v| [k.sub(/^HTTP_/, ''), v]}
                      .collect {|k,v| [k.split('_').collect(&:capitalize).join('-'), v]}
                      .sort
                      .flatten]

  if request.env["rack.attack.match_type"] == :throttle
    Rails.logger.info "[Rack::Attack][Blocked] name: #{name}, remote_ip: \"#{request.remote_ip}\", path: \"#{request.path}\", headers: #{headers.inspect}"
  end
end
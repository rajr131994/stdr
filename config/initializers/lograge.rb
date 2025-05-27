require 'lograge/sql/extension'

Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new

  config.lograge.custom_payload do |controller|
    headers = Hash[*controller.request.env.select {|k,v| k.start_with? 'HTTP_'}
                        .collect {|k,v| [k.sub(/^HTTP_/, ''), v]}
                        .collect {|k,v| [k.split('_').collect(&:capitalize).join('-'), v]}
                        .sort
                        .flatten]
    {
        request_params: controller.request.filtered_parameters,
        headers: headers
    }
  end

  # Instead of extracting event as Strings, extract as Hash. You can also extract
  # additional fields to add to the formatter
  config.lograge_sql.extract_event = Proc.new do |event|
    sql_params = event.payload[:binds].map{|bind| bind.value}
    { name: event.payload[:name], duration: event.duration.to_f.round(2), sql: event.payload[:sql], sql_params: sql_params }
  end

  config.lograge.base_controller_class = ['ActionController::Base']
  config.lograge.ignore_actions = ["HealthCheck::HealthCheckController#index"]

end
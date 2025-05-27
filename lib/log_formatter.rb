# frozen_string_literal: true

# Custom logger, Formats logs and add severity and datetime fields
class LogFormatter
  include ActiveSupport::TaggedLogging::Formatter

  LOG_FIELDS = { datetime: 'datetime', severity: 'severity' }.freeze

  def call(severity, timestamp, _progname, message)
    json_log = formatted_json(message)
    if json_log
      json_log[LOG_FIELDS[:datetime]] = timestamp.gmtime unless json_log.key? LOG_FIELDS[:datetime]
      json_log[LOG_FIELDS[:severity]] = severity unless json_log.key? LOG_FIELDS[:severity]
      write_log(json_log.to_json)
    else
      write_log(message)
    end
  rescue StandardError => _e
    write_log(message)
  end

  def formatted_json(message)
    JSON.parse(message)
  rescue JSON::ParserError => _e
    false
  end

  def write_log(message)
    message = "#{tags_text}#{message}"
    "#{message.is_a?(String) ? message : message.inspect}\n"
  end
end

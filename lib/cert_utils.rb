require 'base64'
require 'openssl'

class CertUtils
  def self.validate_client_cert(base64_encoded_cert, client_cert_password)
    if base64_encoded_cert.nil? or base64_encoded_cert.empty?
      raise 'Please provide a valid certificate along with correct password.'
    end

    begin
      decoded_cert = Base64.decode64(base64_encoded_cert)
      p12 = OpenSSL::PKCS12.new(decoded_cert, client_cert_password)
    rescue Exception => ex
      logger.error("failed to load the certificate. Error: #{ex.message}")
      raise "Please provide a valid certificate along with correct password. Error: #{ex.message}"
    end

    if p12.nil? || p12.certificate.nil?
      raise "Invalid Client certificate. Please update the connection profile with valid certificate."
    end

    client_cert = p12.certificate
    ca_certs = p12.ca_certs

    if client_cert.not_after < Time.now
      raise "Client certificate expired on #{client_cert.not_after}. Please update the connection profile with valid certificate."
    end

    unless ca_certs.nil?
      ca_certs.each do |cert|
        if cert.not_after < Time.now
          raise "Certificate CN:#{cert.subject.to_a.find { |item| item[0] == 'CN' }[1]} expired on #{cert.not_after}. Please update the connection profile with valid certificate."
        end
      end
    end
  end

  def self.get_cert_details(base64_encoded_cert, client_cert_password)
    if base64_encoded_cert.nil? or base64_encoded_cert.empty?
      raise 'Please provide a valid certificate along with correct password.'
    end

    begin
      decoded_cert = Base64.decode64(base64_encoded_cert)
      p12 = OpenSSL::PKCS12.new(decoded_cert, client_cert_password)
    rescue Exception => ex
      logger.error("failed to load the certificate. Error: #{ex.message}")
      raise "Please provide a valid certificate along with correct password. Error: #{ex.message}"
    end

    if p12.nil? || p12.certificate.nil?
      raise "Invalid Client certificate. Please update the connection profile with valid certificate."
    end

    client_cert = p12.certificate
    ca_certs = p12.ca_certs

    client_cert_info = []
    client_cert_info << {
      type: 'Client Certificate',
      validity: client_cert.not_after,
      issuer: client_cert.subject.to_a.find { |item| item[0] == 'CN' }[1]
    }

    unless ca_certs.nil?
      ca_certs.each do |cert|
        client_cert_info << {
          type: cert.issuer == cert.subject ? 'Root Certificate' : 'Intermediate Certificate',
          validity: cert.not_after,
          issuer: cert.subject.to_a.find { |item| item[0] == 'CN' }[1]
        }
      end
    end

    return client_cert_info
  end
end

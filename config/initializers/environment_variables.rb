unless Rails.env.production?
  ENV['BL_LINK_URL'] = ENV['USING_DOCKER'] ? "http://172.16.0.1:3000" : "http://localhost:3000/"
  ENV['STS_URL'] = "https://api.g02d10.blacklinecloud.dev"
  ENV['STS_CERT_LOCATION'] = "#{Rails.root}/dev_certs/local_dev.pfx"
  ENV['STS_CERT_PASSPHRASE'] = Rails.application.credentials.dev[:sts_cert_passphrase]
  ENV['STS_BLLINK_SCOPE'] = "BLLink"
  ENV['STS_BLLINK_SCOPE_SECRET'] = "Pa$$w0rd"
  ENV['STS_BLLINKTOCONNECTOR_SCOPE'] = "BLLinkToConnector"
  ENV['ACCEPTED_SCOPES'] = "BLLink,BLLinkToConnector"
  ENV['REDIS_SERVER_HOSTS'] = "127.0.0.1"
  ENV['REDIS_SERVER_PASSWORD'] = ''
  ENV['ENV_TYPE'] = 'DEV'
  ENV['BL_API_BASE_URL'] = "https://d10.api.blackline.corp"
  ENV["REDIS_SENTINEL_HOSTS"] = "las"
  ENV['BL_ENV_NAME'] = 'd10'
  ENV['SCP_ENV_TYPE'] = "DEV"

  ENV['SCP_DEST_API_CLIENT_ID'] = "sb-cloneccf68adc417b4aa79ae943f70ed030d9!b559|destination-xsappname!b24"
  ENV['SCP_DEST_API_SECRET'] = "ujbwMDLSs+yPeK8mke8Z8+keWVg="
  ENV['SCP_DEST_METHOD'] = "https:"
  ENV['SCP_DEST_API_HOST'] = "//destination-configuration.cfapps.us30.hana.ondemand.com"
  ENV['SCP_DEST_API_ENDPOINT'] = "/destination-configuration/v1/subaccountDestinations"
  ENV['SCP_DEST_API_TOKEN_PREFIX_HOST'] = "//"
  ENV['SCP_DEST_API_TOKEN_HOST'] = ".authentication.us30.hana.ondemand.com"
  ENV['SCP_DEST_API_TOKEN_ENDPOINT'] = "/oauth/token?grant_type=client_credentials"
  ENV['SCP_SUB_ACCOUNT'] = "11111111"
  ENV['RESQUE_WEB_HTTP_BASIC_AUTH_USER'] = "resqueadmin"
  ENV['RESQUE_WEB_HTTP_BASIC_AUTH_PASSWORD'] = "Runbook01"
  ENV['ALLOWED_SAP_RESQUE_SUBNET'] = "127.0.0.0/24"
  ENV['IP_WHITELIST'] = ""
  ENV['BL_API_BASE_URL'] = "https://d10.api.blackline.corp"
  ENV['STS_INTROSPECT_ENDPOINT'] = "/authorize/connect/introspect"
  ENV['STS_SCOPE_NAME'] = "DataIngestionAPI"
  ENV['STS_SCOPE_SECRET'] = "StsSapConnector"
  ENV['STS_S4H_API_HOST'] = "https://sap.connectors.dev.blackline.com"
  ENV['STS_TOKEN_HOST'] = "https://d10.api.blackline.com"
  ENV['STS_TOKEN_ENDPOINT'] = "/authorize/connect/token"
  ENV['STS_CLIENT_ID'] = "StsSapConnector"
  ENV['STS_CLIENT_SECRET'] = "StsSapConnector"

  ENV['EXTRACTOR_HOST_URI'] = "http://localhost:8080"
  ENV['JOURNALS_HOST_URI'] = "http://localhost:8080"

  ENV['EXTRACTOR_CLOUD_PLATFORM'] = 'BTP'

end
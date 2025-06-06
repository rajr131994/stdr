# frozen_string_literal: true

# You can have Apartment route to the appropriate Tenant by adding some Rack middleware.
# Apartment can support many different "Elevators" that can take care of this routing to your data.
# Require whichever Elevator you're using below or none if you have a custom one.
#
require 'apartment/elevators/generic'
# require 'apartment/elevators/domain'
# require 'apartment/elevators/subdomain'
# require 'apartment/elevators/first_subdomain'
# require 'apartment/elevators/host'
require 'rescued_apartment_middleware'
#
# Apartment Configuration
#
Apartment.configure do |config|

  # Add any models that you do not want to be multi-tenanted, but remain in the global (public) namespace.
  # A typical example would be a Customer or Tenant model that stores each Tenant's information.
  #
  #config.excluded_models = %w{ ConnectorInstance Deftype DeftypeLine Definition DefLine }
  config.excluded_models = %w{ ConnectorInstance ScpConnection ApiConnection }

  # In order to migrate all of your Tenants you need to provide a list of Tenant names to Apartment.
  # You can make this dynamic by providing a Proc object to be called on migrations.
  # This object should yield either:
  # - an array of strings representing each Tenant name.
  # - a hash which keys are tenant names, and values custom db config (must contain all key/values required in database.yml)
  #
  # config.tenant_names = lambda{ Customer.pluck(:tenant_name) }
  # config.tenant_names = ['tenant1', 'tenant2']
  # config.tenant_names = {
  #   'tenant1' => {
  #     adapter: 'postgresql',
  #     host: 'some_server',
  #     port: 5555,
  #     database: 'postgres' # this is not the name of the tenant's db
  #                          # but the name of the database to connect to before creating the tenant's db
  #                          # mandatory in postgresql
  #   },
  #   'tenant2' => {
  #     adapter:  'postgresql',
  #     database: 'postgres' # this is not the name of the tenant's db
  #                          # but the name of the database to connect to before creating the tenant's db
  #                          # mandatory in postgresql
  #   }
  # }
  # config.tenant_names = lambda do
  #   Tenant.all.each_with_object({}) do |tenant, hash|
  #     hash[tenant.name] = tenant.db_configuration
  #   end
  # end
  #
  config.tenant_names = lambda { ConnectorInstance.pluck :id }

  config.seed_after_create = true
  # PostgreSQL:
  #   Specifies whether to use PostgreSQL schemas or create a new database per Tenant.
  #
  # MySQL:
  #   Specifies whether to switch databases by using `use` statement or re-establish connection.
  #
  # The default behaviour is true.
  #
  # config.use_schemas = true

  #
  # ==> PostgreSQL only options

  # Apartment can be forced to use raw SQL dumps instead of schema.rb for creating new schemas.
  # Use this when you are using some extra features in PostgreSQL that can't be represented in
  # schema.rb, like materialized views etc. (only applies with use_schemas set to true).
  # (Note: this option doesn't use db/structure.sql, it creates SQL dump by executing pg_dump)
  #
  # config.use_sql = false

  # There are cases where you might want some schemas to always be in your search_path
  # e.g when using a PostgreSQL extension like hstore.
  # Any schemas added here will be available along with your selected Tenant.
  #
  # config.persistent_schemas = %w{ hstore }

  # <== PostgreSQL only options
  #

  # By default, and only when not using PostgreSQL schemas, Apartment will prepend the environment
  # to the tenant name to ensure there is no conflict between your environments.
  # This is mainly for the benefit of your development and test environments.
  # Uncomment the line below if you want to disable this behaviour in production.
  #
  # config.prepend_environment = !Rails.env.production?

  # When using PostgreSQL schemas, the database dump will be namespaced, and
  # apartment will substitute the default namespace (usually public) with the
  # name of the new tenant when creating a new tenant. Some items must maintain
  # a reference to the default namespace (ie public) - for instance, a default
  # uuid generation. Uncomment the line below to create a list of namespaced
  # items in the schema dump that should *not* have their namespace replaced by
  # the new tenant
  #
  # config.pg_excluded_names = ["uuid_generate_v4"]

  # Specifies whether the database and schema (when using PostgreSQL schemas) will prepend in ActiveRecord log.
  # Uncomment the line below if you want to enable this behavior.
  #
  # config.active_record_log = true
end

Apartment::Elevators::Generic.prepend RescuedApartmentMiddleware
# Setup a custom Tenant switching middleware. The Proc should return the name of the Tenant that
# you want to switch to.
Rails.application.config.middleware.use Apartment::Elevators::Generic, lambda { |request|

  # Get headers
  puts "This is the request path: " + request.path
  non_restricted_paths = ["/api/v1/connector_instances","/health_check","/resque","/sap_health_check", "/journals/post","/journals/check", "/versionz", "/healthz"]
  puts "non_restricted_paths are: " + non_restricted_paths.to_s
  if non_restricted_paths.any? { |path| request.path.include? path }
    puts "non restricted path!!"
    return "public"
  else

    headers = Hash[*request.env.select {|k,v| k.start_with? 'HTTP_'}
                        .collect {|k,v| [k.sub(/^HTTP_/, ''), v]}
                        .collect {|k,v| [k.split('_').collect(&:capitalize).join('-'), v]}
                        .sort
                        .flatten]

    # request is an instance of Rack::Request
    puts headers.inspect
    puts "connector instance: #{headers.with_indifferent_access['Connector-Instance']}"
    if headers['Connector-Instance'] == nil
      #fail StandardError, "Connector Instance header is not found in the request '#{headers.with_indifferent_access['Connector-Instance']}'"
      raise Apartment::TenantNotFound
      return Apartment::Tenant.current
    end

    # example: look up some tenant from the db based on this request
    tenant = ConnectorInstance.find_by(id: headers.with_indifferent_access['Connector-Instance'])
    #fail StandardError, "Connector Instance is not found with Id: '#{headers.with_indifferent_access['Connector-Instance']}'" if tenant.blank?
    raise Apartment::TenantNotFound if tenant.blank?
    return tenant.id
  end
}
# Rails.application.config.middleware.use Apartment::Elevators::Domain
# Rails.application.config.middleware.use Apartment::Elevators::Subdomain
# Rails.application.config.middleware.use Apartment::Elevators::FirstSubdomain
# Rails.application.config.middleware.use Apartment::Elevators::Host

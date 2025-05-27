#module LinkEngine
class Sts
  include HTTParty
  # To get http requests logged
  debug_output $stdout
  # Hard coding links to test, but these should be made dynamic on an instance by instance basis
  base_uri ENV['STS_URL']
  default_options.update(verify: false)
end
#end

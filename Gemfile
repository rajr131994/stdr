source 'https://artifactory.blackline.com/artifactory/api/gems/Ruby_Gems_Remote/'

ruby '3.1.4'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 7.1', '>= 7.1.4.1'
# Use postgresql as the database for Active Record
gem 'pg', '>= 0.18', '< 2.0'
# Use Puma as the app server
#gem 'puma', '~> 5.6', '>= 5.6.8'
gem 'puma', '~> 6.4.3'
# Use SCSS for stylesheets
gem 'sass-rails', '~> 6.0.0'
# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '>= 1.3.0'
# See https://github.com/rails/execjs#readme for more supported runtimes
# gem 'mini_racer', platforms: :ruby

# Use CoffeeScript for .coffee assets and views
gem 'coffee-rails', '~> 4.2'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.12.0'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'
# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'
gem 'fugit', '~> 1.11', '>= 1.11.1'

# Use ActiveStorage variant
# gem 'mini_magick', '~> 4.8'
gem 'nokogiri', '1.16.5'
# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

# ruby gem for integratinbg with new relic
gem 'newrelic_rpm'

# Logging
gem 'lograge'
gem 'lograge-sql'
gem 'rack', '3.1.14'

# Reduces boot times through caching; required in config/boot.rb
#gem 'bootsnap', '>= 1.1.0', require: false

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
end

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '3.7.1'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring', '~> 4.1'
  gem 'spring-watcher-listen', '~> 2.1'
end

group :test do
  # Adds support for Capybara system testing and selenium driver
  #gem 'capybara', '>= 2.15'
  #gem 'selenium-webdriver'
  # Easy installation and use of chromedriver to run system tests with Chrome
  gem 'chromedriver-helper'
    #gem 'webdrivers', '~> 3.0'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

# gem "apartment"
gem 'ros-apartment', require: 'apartment'
gem "httparty"
gem "health_check"
#gem "attr_encrypted"
gem 'redis', '4.5.1'
source 'https://artifactory.blackline.com/artifactory/api/gems/Ruby_Gems/' do
  gem "blackline_logging"
  gem 'resque-scheduler', '4.10.2'
end
#gem "link_engine"
gem 'rack-cors', :require => 'rack/cors'
gem 'mustermann', '~> 3.0'
gem 'resque', '~> 2.6'
gem 'sinatra', '>= 2.2.0'
gem 'resque-pool'
gem 'resque-scheduler-web'
gem 'activejob', '~>  7.1.4.1'
gem 'cronex'
gem 'rest-client'
gem 'json'
gem 'redis-rails'
gem 'rails-controller-testing'
gem 'resque-web'
gem 'redis-store', '1.10'
gem 'minitest', '~> 5.15.0'
# gem 'date', '3.3.1' if Gem.ruby_version < Gem::Version.new('2.6.0')
# gem 'net-protocol', '0.1.2' if Gem.ruby_version < Gem::Version.new('2.6.0')
#
gem 'net-imap', '0.5.7'
# gem 'net-smtp', '0.3.0' if Gem.ruby_version < Gem::Version.new('2.6.0')
gem 'public_suffix', '4.0.7'
gem 'bootsnap', '1.13.0'
#gem 'mustermann', '2.0.2'
gem 'attr_encrypted', '~> 4.0'
gem 'sprockets-rails', :require => 'sprockets/railtie'

# NOTE(Marin): used for rate limiting APIs in combination with redis-rails
gem 'rack-attack'

gem 'webrick', '~> 1.9.0'

#gem 'apartment', github: 'influitive/apartment', branch: 'development'
# Run against the latest stable release
group :development, :test do
  gem 'rspec-rails', ">= 6.0.3"
end

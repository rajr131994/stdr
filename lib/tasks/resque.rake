require 'resque/tasks'
require 'resque/scheduler/tasks'
require 'resque/pool/tasks'

task "resque:setup" => :environment do

  # Resque.before_fork = Proc.new do |job|
  #   ActiveRecord::Base.connection.disconnect!
  # end
  # Resque.after_fork = Proc.new do |job|
  #   ActiveRecord::Base.establish_connection
  # end
  Resque::Scheduler.dynamic = true

end

task "resque:pool:setup" do
  # close any sockets or files in pool manager
  ActiveRecord::Base.connection.disconnect!
  # and re-open them in the resque worker parent
  Resque::Pool.after_prefork do |job|
    ActiveRecord::Base.establish_connection
  end
end

task "resque:pool:setup" do
  Resque::Pool.after_prefork do |job|
    Resque.redis.client.reconnect
  end
end

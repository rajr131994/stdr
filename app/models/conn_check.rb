class ConnCheck

    attr_accessor :blackline_instance_id
    attr_accessor :tenant
    attr_accessor :message
    attr_accessor :oauthToken
    attr_accessor :selectClause
    attr_accessor :segments

    attr_accessor :destination

    def initialize(destination,blackline_instance_id,tenant,message,oauthToken)

      @destination = destination
      @tenant = tenant
      @message = message
      @oauthToken = oauthToken
      @selectClause = []
      @segments = []
      @blackline_instance_id = blackline_instance_id

    end

    def to_json(*options)
      as_json(*options).to_json(*options)
    end

    def persisted?
       false
    end

end
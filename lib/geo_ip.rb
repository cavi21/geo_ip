require 'json'
require 'typhoeus'

class GeoIp
  SERVICE_URL = 'http://api.ipinfodb.com/v3/ip-'
  CITY_API    = 'city'
  COUNTRY_API = 'country'
  IPV4_REGEXP = /\A(?:25[0-5]|(?:2[0-4]|1\d|[1-9])?\d)(?:\.(?:25[0-5]|(?:2[0-4]|1\d|[1-9])?\d)){3}\z/

  @@api_key = nil
  @@timeout = 1
  @@fallback_timeout = 3

  class << self
    def api_key
      @@api_key
    end

    def api_key= api_key
      @@api_key = api_key
    end

    def timeout
      @@timeout
    end

    def timeout= timeout
      @@timeout = timeout
    end

    def fallback_timeout
      @@fallback_timeout
    end

    def fallback_timeout= fallback_timeout
      @@fallback_timeout = fallback_timeout
    end

    def set_defaults_if_necessary options
      options[:precision] ||= :city
      options[:timezone]  ||= false
      raise 'Invalid precision'  unless [:country, :city].include?(options[:precision])
      raise 'Invalid timezone'   unless [true, false].include?(options[:timezone])
    end

    def lookup_url ip, options = {}
      set_defaults_if_necessary options
      raise 'API key must be set first: GeoIp.api_key = \'YOURKEY\'' if self.api_key.nil?
      raise 'Invalid IP address' unless ip.to_s =~ IPV4_REGEXP

      "#{SERVICE_URL}#{options[:precision] == :city || options[:timezone] ? CITY_API : COUNTRY_API}?key=#{api_key}&ip=#{ip}&format=json&timezone=#{options[:timezone]}"
    end

    # Retreive the remote location of a given ip address.
    #
    # It takes two optional arguments:
    # * +preceision+: can either be +:city+ (default) or +:country+
    # * +timezone+: can either be +false+ (default) or +true+
    #
    # ==== Example:
    #   GeoIp.geolocation('209.85.227.104', {:precision => :city, :timezone => true})
    def geolocation ip, options={}
      location = nil
      request = Typhoeus::Request.new(lookup_url(ip, options),
                                      :method => :get,
                                      :timeout => self.timeout, # miliseconds
                                      :cache_timeout => 60) # seconds
      request.on_complete do |response|
        if response.success?
          parsed_response = JSON.parse response.body
        elsif response.timed_out?
          parsed_response = Hash["latitude"=>"-", "statusMessage"=>"Timeout", "cityName"=>"-", "regionName"=>"-", "ipAddress"=>"-", "timeZone"=>"-", "zipCode"=>"-", "countryCode"=>"-", "countryName"=>"-", "longitude"=>"-", "statusCode"=>"ERROR"]
        else
          parsed_response = Hash["latitude"=>"-", "statusMessage"=>"Unknown Error", "cityName"=>"-", "regionName"=>"-", "ipAddress"=>"-", "timeZone"=>"-", "zipCode"=>"-", "countryCode"=>"-", "countryName"=>"-", "longitude"=>"-", "statusCode"=>"ERROR"]
        end
        location = convert_keys(parsed_response, options)
      end
      hydra = Typhoeus::Hydra.new
      hydra.queue(request)
      hydra.run

      location
    end

    private
    def convert_keys hash, options
      set_defaults_if_necessary options
      location = {}
      location[:ip]             = hash['ipAddress']
      location[:status_code]    = hash['statusCode']
      location[:status_message] = hash['statusMessage']
      location[:country_code]   = hash['countryCode']
      location[:country_name]   = hash['countryName']
      if options[:precision] == :city
        location[:region_name]  = hash['regionName']
        location[:city]         = hash['cityName']
        location[:zip_code]     = hash['zipCode']
        location[:latitude]     = hash['latitude']
        location[:longitude]    = hash['longitude']
        if options[:timezone]
          location[:timezone]   = hash['timeZone']
        end
      end
      location
    end
  end
end

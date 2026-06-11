module AntiFraud
  # Resolve IP → (lat, lng, cidade) usando MaxMind GeoLite2-City.
  # Thread-safe via singleton.  Retorna nil silenciosamente se a base
  # não existe ou se o IP é privado/localhost.
  class GeoIpResolver
    DB_PATH = Rails.root.join("db", "geoip", "GeoLite2-City.mmdb")

    def self.instance
      @instance ||= new
    end

    def self.lookup(ip)
      instance.lookup(ip)
    end

    def initialize
      @reader = nil
      if File.exist?(DB_PATH)
        require "maxmind/db"
        @reader = MaxMind::DB.new(DB_PATH.to_s, mode: MaxMind::DB::MODE_MEMORY)
      end
    rescue LoadError, StandardError => e
      Rails.logger.warn("[GeoIpResolver] Inicialização falhou: #{e.message}")
      @reader = nil
    end

    def lookup(ip)
      return nil if @reader.nil? || ip.to_s.strip.empty?
      return nil if private_ip?(ip)

      data = @reader.get(ip.to_s)
      return nil unless data

      {
        latitude: data.dig("location", "latitude"),
        longitude: data.dig("location", "longitude"),
        city: data.dig("city", "names", "en"),
        country: data.dig("country", "iso_code")
      }
    rescue => e
      Rails.logger.warn("[GeoIpResolver] Erro no lookup de #{ip}: #{e.message}")
      nil
    end

    private

    def private_ip?(ip)
      addr = IPAddr.new(ip.to_s)
      addr.loopback? || addr.private?
    rescue IPAddr::InvalidAddressError
      true
    end
  end
end

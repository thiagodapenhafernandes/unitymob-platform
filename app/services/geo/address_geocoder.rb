# frozen_string_literal: true

require "json"
require "net/http"

module Geo
  class AddressGeocoder
    Result = Data.define(:latitude, :longitude, :display_name, :house_number, :provider, :precision)
    # Status do Google que indicam problema de configuração/cota (não "endereço não achado").
    GOOGLE_BLOCKING_STATUSES = %w[REQUEST_DENIED OVER_DAILY_LIMIT OVER_QUERY_LIMIT INVALID_REQUEST].freeze

    # Último status/erro da chamada ao Google, para quem precisa diagnosticar
    # (ex.: chave com restrição de referenciador devolve REQUEST_DENIED).
    attr_reader :google_status, :google_error

    # Nominatim (OpenStreetMap) aceita no máximo 1 requisição por segundo.
    NOMINATIM_INTERVAL = 1.1

    # provider: "leaflet" usa só o Nominatim (gratuito, OpenStreetMap), sem
    # cair numa chave Google do ambiente; nil mantém Google com fallback.
    def initialize(address:, number:, neighborhood:, city:, state:, zip_code:, country: "Brasil", api_key: nil, provider: nil)
      @api_key = api_key
      @provider = provider.to_s
      @address = address.to_s.strip
      @number = number.to_s.strip
      @neighborhood = neighborhood.to_s.strip
      @city = city.to_s.strip
      @state = state.to_s.strip
      @zip_code = zip_code.to_s.gsub(/\D/, "")
      @country = country.to_s.strip.presence || "Brasil"
    end

    # Último recurso: centro do bairro pelo OpenStreetMap (precision
    # "neighborhood"). Só para mostrar região aproximada no mapa.
    def neighborhood_call
      return if neighborhood.blank? || city.blank?

      sleep(NOMINATIM_INTERVAL) # costuma vir logo depois das tentativas da rua
      # Só bairros/localidades (featureType=settlement) e sem o país no texto:
      # busca livre casava com comércio ("Brasil Atacadista") e praias vizinhas.
      data = json_get("https://nominatim.openstreetmap.org/search",
                      q: [neighborhood, city, state].select(&:present?).join(", "),
                      format: "json", limit: 3, countrycodes: "br", layer: "address",
                      featureType: "settlement", addressdetails: 1)
      match = Array(data).find { |item| item.is_a?(Hash) && same_city?(item["address"]) }
      return unless match

      Result.new(latitude: match["lat"], longitude: match["lon"], display_name: match["display_name"],
                 house_number: nil, provider: "osm", precision: "neighborhood")
    rescue StandardError => e
      Rails.logger.warn("[geo.address_geocoder] neighborhood_failed class=#{e.class} message=#{e.message}")
      nil
    end

    # Leaflet: só OpenStreetMap. Google: se não resolver (chave recusada,
    # cota, endereço não achado), tenta a rua no OpenStreetMap antes de desistir.
    def call
      return nominatim_result if @provider == "leaflet"

      google_result || nominatim_result
    end

    private

    attr_reader :address, :number, :neighborhood, :city, :state, :zip_code, :country

    def google_result
      key = @api_key.presence || ENV["GOOGLE_MAPS_API_KEY"].presence || ENV["GOOGLE_GEOCODING_API_KEY"].presence
      return nil if key.blank?

      data = json_get(
        "https://maps.googleapis.com/maps/api/geocode/json",
        address: full_address,
        components: google_components,
        key:
      )
      @google_status = data.is_a?(Hash) ? data["status"] : "INVALID_RESPONSE"
      @google_error = data["error_message"] if data.is_a?(Hash)
      if @google_status.in?(GOOGLE_BLOCKING_STATUSES)
        Rails.logger.warn("[geo.address_geocoder] google_#{@google_status.downcase} message=#{@google_error}")
      end
      return nil unless @google_status == "OK"

      first = data["results"]&.first
      location = first&.dig("geometry", "location")
      return nil unless location

      Result.new(
        latitude: location["lat"],
        longitude: location["lng"],
        display_name: first["formatted_address"],
        house_number: google_component(first, "street_number"),
        provider: "google",
        precision: first.dig("geometry", "location_type").to_s.downcase.presence || "unknown"
      )
    rescue StandardError => e
      Rails.logger.warn("[geo.address_geocoder] google_failed class=#{e.class} message=#{e.message}")
      nil
    end

    def nominatim_result
      nominatim_requests.each_with_index do |request, index|
        sleep(NOMINATIM_INTERVAL) if index.positive?
        data = json_get("https://nominatim.openstreetmap.org/search", request)
        next unless data.is_a?(Array) && data.first

        first = data.first
        return Result.new(
          latitude: first["lat"],
          longitude: first["lon"],
          display_name: first["display_name"],
          house_number: first.dig("address", "house_number"),
          provider: "osm",
          precision: first.dig("address", "house_number").present? ? "house_number" : "street"
        )
      end

      nil
    rescue StandardError => e
      Rails.logger.warn("[geo.address_geocoder] nominatim_failed class=#{e.class} message=#{e.message}")
      nil
    end

    def nominatim_requests
      base = {
        format: "json",
        limit: 1,
        countrycodes: "br",
        addressdetails: 1
      }

      requests = []
      if address.present? && number.present?
        requests << base.merge(street: "#{number} #{address}", city:, state:, postalcode: zip_code, country:)
        requests << base.merge(street: "#{address}, #{number}", city:, state:, postalcode: zip_code, country:)
      end
      requests << base.merge(q: full_address)
      requests
    end

    def full_address
      street_line = [address, number].select(&:present?).join(", ")
      city_line = [city, state].select(&:present?).join("/")
      [street_line, neighborhood, city_line, zip_code.presence, country].select(&:present?).join(" - ")
    end

    # O bairro precisa estar na cidade do cadastro (evita ponto em outra cidade).
    def same_city?(address_details)
      normalize = ->(value) { I18n.transliterate(value.to_s).downcase.strip }
      found = %w[city town municipality village].filter_map { |key| address_details.to_h[key] }
      found.any? { |value| normalize.call(value) == normalize.call(city) }
    end

    def google_components
      components = ["country:BR"]
      components << "postal_code:#{zip_code}" if zip_code.present?
      components.join("|")
    end

    def google_component(result, type)
      result["address_components"]&.find { |component| component["types"]&.include?(type) }&.dig("long_name")
    end

    def json_get(url, params)
      uri = URI(url)
      uri.query = URI.encode_www_form(params.compact_blank)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = "UnitymobCRM/1.0 geocoder"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
      JSON.parse(response.body)
    end
  end
end

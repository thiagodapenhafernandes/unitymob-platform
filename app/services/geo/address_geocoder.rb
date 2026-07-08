# frozen_string_literal: true

require "json"
require "net/http"

module Geo
  class AddressGeocoder
    Result = Data.define(:latitude, :longitude, :display_name, :house_number, :provider, :precision)

    def initialize(address:, number:, neighborhood:, city:, state:, zip_code:, country: "Brasil")
      @address = address.to_s.strip
      @number = number.to_s.strip
      @neighborhood = neighborhood.to_s.strip
      @city = city.to_s.strip
      @state = state.to_s.strip
      @zip_code = zip_code.to_s.gsub(/\D/, "")
      @country = country.to_s.strip.presence || "Brasil"
    end

    def call
      google_result || nominatim_result
    end

    private

    attr_reader :address, :number, :neighborhood, :city, :state, :zip_code, :country

    def google_result
      key = ENV["GOOGLE_MAPS_API_KEY"].presence || ENV["GOOGLE_GEOCODING_API_KEY"].presence
      return nil if key.blank?

      data = json_get(
        "https://maps.googleapis.com/maps/api/geocode/json",
        address: full_address,
        components: google_components,
        key:
      )
      return nil unless data.is_a?(Hash) && data["status"] == "OK"

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
      nominatim_requests.each do |request|
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

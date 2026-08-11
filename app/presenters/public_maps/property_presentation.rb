require "openssl"

module PublicMaps
  class PropertyPresentation
    MAP_DISPLAY_MODES = %w[inherit hidden approximate exact].freeze
    STREET_VIEW_MODES = %w[inherit enabled disabled].freeze

    attr_reader :property, :setting

    def initialize(property, setting: nil)
      @property = property
      @setting = setting || GoogleMapsIntegrationSetting.for(property.tenant)
    end

    def visible?
      exact_coordinates.present? && display_mode != "hidden"
    end

    def provider
      setting.configured? ? setting.provider : GoogleMapsIntegrationSetting::DEFAULT_PROVIDER
    end

    def display_mode
      property_mode = property.public_map_display_mode.to_s
      return setting.default_display_mode if property_mode.blank? || property_mode == "inherit"

      property_mode
    end

    def center_coordinates
      return unless visible?
      return exact_coordinates if display_mode == "exact"

      approximate_coordinates
    end

    def radius_meters
      display_mode == "approximate" ? setting.approximate_radius_meters : 0
    end

    def zoom
      setting.default_zoom
    end

    def satellite_enabled?
      provider == "google" && setting.satellite_enabled?
    end

    def street_view_enabled?
      return false unless provider == "google"

      case property.public_street_view_mode.to_s
      when "enabled" then true
      when "disabled" then false
      else !approximate? && setting.street_view_enabled?
      end
    end

    def external_link_enabled?
      setting.external_link_enabled?
    end

    def api_key
      setting.api_key if provider == "google"
    end

    def street_view_coordinates
      exact_coordinates if street_view_enabled?
    end

    def external_url
      return unless external_link_enabled? && center_coordinates.present?

      latitude, longitude = center_coordinates
      formatted_latitude = format("%.7f", latitude)
      formatted_longitude = format("%.7f", longitude)

      if provider == "google"
        "https://www.google.com/maps/search/?api=1&query=#{formatted_latitude},#{formatted_longitude}"
      else
        "https://www.openstreetmap.org/?mlat=#{formatted_latitude}&mlon=#{formatted_longitude}#map=#{zoom}/#{formatted_latitude}/#{formatted_longitude}"
      end
    end

    def approximate?
      display_mode == "approximate"
    end

    private

    def exact_coordinates
      latitude, longitude = coordinate_candidates
      return unless latitude.between?(-90, 90) && longitude.between?(-180, 180)
      return if latitude.zero? && longitude.zero?

      [latitude, longitude]
    end

    def coordinate_candidates
      address_latitude = numeric_coordinate(property.address&.latitude)
      address_longitude = numeric_coordinate(property.address&.longitude)
      return [address_latitude, address_longitude] if address_latitude && address_longitude

      [
        numeric_coordinate(attribute_coordinate(:latitude)),
        numeric_coordinate(attribute_coordinate(:longitude))
      ]
    end

    def attribute_coordinate(name)
      return unless property.has_attribute?(name)

      property.read_attribute(name)
    end

    def numeric_coordinate(value)
      return if value.blank?

      BigDecimal(value.to_s).to_f
    rescue ArgumentError
      nil
    end

    def approximate_coordinates
      latitude, longitude = exact_coordinates
      digest = OpenSSL::HMAC.digest("SHA256", Rails.application.secret_key_base, "public-map:#{property.tenant_id}:#{property.id}")
      angle = digest.unpack1("Q>").fdiv((2**64) - 1) * 2 * Math::PI
      distance_ratio = 0.45 + (digest.byteslice(8, 8).unpack1("Q>").fdiv((2**64) - 1) * 0.4)
      distance_meters = radius_meters * distance_ratio
      latitude_offset = (distance_meters * Math.cos(angle)) / 111_320.0
      longitude_scale = 111_320.0 * Math.cos(latitude * Math::PI / 180.0).abs.clamp(0.01, 1.0)
      longitude_offset = (distance_meters * Math.sin(angle)) / longitude_scale

      [latitude + latitude_offset, longitude + longitude_offset]
    end
  end
end

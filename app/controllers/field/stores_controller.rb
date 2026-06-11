# frozen_string_literal: true

module Field
  class StoresController < BaseController
    before_action :ensure_field_enabled!
    before_action :ensure_field_agent!

    # GET /field/stores/discover?lat=...&lng=...
    # Retorna a loja mais próxima dentro do raio do corretor (ou a mais próxima
    # se nenhuma estiver no raio), com distância em metros.
    def discover
      lat = params[:lat]
      lng = params[:lng]

      if lat.blank? || lng.blank?
        render json: { error: "missing_coordinates" }, status: :unprocessable_entity
        return
      end

      nearest = Store.by_distance_from(lat, lng).limit(5).map do |s|
        distance = s["distance_meters"].to_f
        {
          id: s.id,
          slug: s.slug,
          name: s.name,
          city: s.city,
          distance_meters: distance.round(1),
          geofence_radius_meters: s.geofence_radius_meters,
          inside_radius: distance <= s.geofence_radius_meters
        }
      end

      render json: { stores: nearest }
    end
  end
end

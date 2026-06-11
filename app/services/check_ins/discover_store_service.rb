# frozen_string_literal: true

module CheckIns
  # Dado lat/lng, retorna:
  #   { store: Store, distance_meters: Float, inside_radius: Boolean }
  # da loja mais próxima, ou nil se não houver nenhuma loja com coordenadas.
  class DiscoverStoreService
    def initialize(lat:, lng:, prefer_store: nil)
      @lat = lat
      @lng = lng
      @prefer_store = prefer_store
    end

    def call
      return nil if @lat.blank? || @lng.blank?

      if @prefer_store&.contains?(@lat, @lng)
        return build_result(@prefer_store)
      end

      nearest = Store.by_distance_from(@lat, @lng).limit(1).first
      return nil unless nearest

      build_result(nearest)
    end

    private

    def build_result(store)
      distance = store["distance_meters"]&.to_f || store.distance_meters_to(@lat, @lng) || 0.0
      {
        store: store,
        distance_meters: distance,
        inside_radius: distance <= store.geofence_radius_meters
      }
    end
  end
end

class HabitationGeocodeJob < ApplicationJob
  queue_as :default

  # Coordenadas do imóvel para o mapa público. Tenta o endereço pelo provedor
  # da conta (Google ou Leaflet/OpenStreetMap); se a rua não for encontrada,
  # usa o centro do bairro marcado como aproximado (Address::NEIGHBORHOOD_PRECISION),
  # que uma geocodificação melhor pode substituir depois. Idempotente.
  def perform(habitation_id, tenant_id:)
    tenant = Tenant.find(tenant_id)
    Current.set(tenant: tenant) do
      habitation = tenant.habitations.find_by(id: habitation_id)
      address = habitation&.address
      return unless address&.coordinates_improvable?
      # Preserva coordenadas vindas do import nas colunas do próprio imóvel
      # (Habitation#latitude delega para o endereço, por isso o [] direto).
      return if habitation[:latitude].present? && habitation[:longitude].present?

      setting = GoogleMapsIntegrationSetting.for(tenant)
      return unless setting.configured?

      snapshot = address.attributes.slice("logradouro", "numero", "bairro", "cidade", "uf", "cep")
      geocoder = Geo::AddressGeocoder.new(
        address: address.logradouro, number: address.numero, neighborhood: address.bairro,
        city: address.cidade, state: address.uf, zip_code: address.cep,
        api_key: (setting.api_key if setting.provider == "google"), provider: setting.provider
      )
      result = geocoder.call
      precision = nil
      unless usable?(result)
        # Já tem o centro do bairro: nada melhor a gravar.
        return if address.neighborhood_coordinates?

        result = geocoder.neighborhood_call
        precision = Address::NEIGHBORHOOD_PRECISION
      end
      return unless usable?(result)

      address.with_lock do
        return unless address.attributes.slice(*snapshot.keys) == snapshot
        return unless address.coordinates_improvable?

        address.update!(latitude: result.latitude, longitude: result.longitude, coordinates_precision: precision)
      end
    end
  end

  private

  def usable?(result)
    return false unless result && result.latitude.present? && result.longitude.present?
    return false unless result.latitude.to_f.between?(-90, 90) && result.longitude.to_f.between?(-180, 180)

    !(result.latitude.to_f.zero? && result.longitude.to_f.zero?)
  end
end

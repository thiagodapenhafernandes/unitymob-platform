class HabitationGeocodeJob < ApplicationJob
  queue_as :default

  # Coordenadas do imóvel para o mapa público. Tenta o endereço pelo provedor
  # da conta (Google, com OpenStreetMap de reserva, ou Leaflet/OpenStreetMap);
  # se a rua não for encontrada, usa o centro do bairro marcado como aproximado.
  # Resultado gravado com a marca de automático (Address::AUTO_PRECISIONS).
  # refresh: o endereço mudou e a coordenada atual (automática) era do antigo;
  # sem resultado para o novo, ela é apagada em vez de apontar para o lugar errado.
  def perform(habitation_id, tenant_id:, refresh: false)
    tenant = Tenant.find(tenant_id)
    Current.set(tenant: tenant) do
      habitation = tenant.habitations.find_by(id: habitation_id)
      address = habitation&.address
      return unless address && workable?(address, refresh)
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
      precision = Address::STREET_PRECISION
      unless usable?(result)
        # Já tem o centro do bairro deste endereço: nada melhor a gravar.
        return if address.neighborhood_coordinates? && !refresh

        result = geocoder.neighborhood_call
        precision = Address::NEIGHBORHOOD_PRECISION
      end
      return unless usable?(result) || refresh

      address.with_lock do
        return unless address.attributes.slice(*snapshot.keys) == snapshot
        return unless workable?(address, refresh)

        address.geocoder_update = true
        if usable?(result)
          address.update!(latitude: result.latitude, longitude: result.longitude, coordinates_precision: precision)
        else
          address.update!(latitude: nil, longitude: nil, coordinates_precision: nil)
        end
      end
    end
  end

  private

  def workable?(address, refresh)
    address.coordinates_improvable? || (refresh && address.auto_geocoded?)
  end

  def usable?(result)
    return false unless result && result.latitude.present? && result.longitude.present?
    return false unless result.latitude.to_f.between?(-90, 90) && result.longitude.to_f.between?(-180, 180)

    !(result.latitude.to_f.zero? && result.longitude.to_f.zero?)
  end
end

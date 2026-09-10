class HabitationGeocodeJob < ApplicationJob
  queue_as :default

  def perform(habitation_id, tenant_id:)
    tenant = Tenant.find(tenant_id)
    Current.set(tenant: tenant) do
      habitation = tenant.habitations.find_by(id: habitation_id)
      address = habitation&.address
      return unless address && (address.latitude.blank? || address.longitude.blank?)
      # Preserve coordinates already provided by an import or a manual map pin.
      return if habitation.latitude.present? && habitation.longitude.present?

      setting = GoogleMapsIntegrationSetting.for(tenant)
      return unless setting.configured? && setting.provider == "google"

      snapshot = address.attributes.slice("logradouro", "numero", "bairro", "cidade", "uf", "cep")
      result = Geo::AddressGeocoder.new(
        address: address.logradouro, number: address.numero, neighborhood: address.bairro,
        city: address.cidade, state: address.uf, zip_code: address.cep, api_key: setting.api_key
      ).call
      return unless result && result.latitude.present? && result.longitude.present?
      return unless result.latitude.to_f.between?(-90, 90) && result.longitude.to_f.between?(-180, 180)
      return if result.latitude.to_f.zero? && result.longitude.to_f.zero?

      address.with_lock do
        return unless address.attributes.slice(*snapshot.keys) == snapshot
        return if address.latitude.present? && address.longitude.present?

        address.update!(latitude: result.latitude, longitude: result.longitude)
      end
    end
  end
end

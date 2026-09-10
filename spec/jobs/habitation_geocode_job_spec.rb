require "rails_helper"

RSpec.describe HabitationGeocodeJob do
  it "preenche coordenadas ausentes e não sobrescreve um ponto manual nem cruza tenants" do
    habitation = create(:habitation, latitude: nil, longitude: nil)
    setting = instance_double(GoogleMapsIntegrationSetting, configured?: true, provider: "google", api_key: "test")
    allow(GoogleMapsIntegrationSetting).to receive(:for).and_return(setting)
    geocoder = instance_double(Geo::AddressGeocoder, call: Geo::AddressGeocoder::Result.new(latitude: -27.0, longitude: -48.6, display_name: "Rua", house_number: "1", provider: "google", precision: "rooftop"))
    allow(Geo::AddressGeocoder).to receive(:new).and_return(geocoder)

    described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id)
    expect(habitation.address.reload.latitude.to_f).to eq(-27.0)
    habitation.address.update!(latitude: -26.9, longitude: -48.5)
    described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id)
    other = Tenant.create!(name: "Other geo", slug: "other-geo-#{SecureRandom.hex(3)}")
    described_class.perform_now(habitation.id, tenant_id: other.id)
    expect(habitation.address.reload.latitude.to_f).to eq(-26.9)
    expect(geocoder).to have_received(:call).once
  end

  it "não salva o resultado quando o endereço muda durante a consulta" do
    habitation = create(:habitation, latitude: nil, longitude: nil)
    allow(GoogleMapsIntegrationSetting).to receive(:for).and_return(instance_double(GoogleMapsIntegrationSetting, configured?: true, provider: "google", api_key: "test"))
    geocoder = instance_double(Geo::AddressGeocoder)
    allow(Geo::AddressGeocoder).to receive(:new).and_return(geocoder)
    allow(geocoder).to receive(:call) do
      habitation.address.update_column(:logradouro, "Outra rua")
      Geo::AddressGeocoder::Result.new(latitude: -27, longitude: -48, display_name: "Rua", house_number: "1", provider: "google", precision: "rooftop")
    end
    described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id)
    expect(habitation.address.reload.latitude).to be_nil
  end
end

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

  it "com Leaflet geocodifica pelo OpenStreetMap, sem chave do Google" do
    habitation = create(:habitation, latitude: nil, longitude: nil)
    setting = instance_double(GoogleMapsIntegrationSetting, configured?: true, provider: "leaflet", api_key: nil)
    allow(GoogleMapsIntegrationSetting).to receive(:for).and_return(setting)
    geocoder = instance_double(Geo::AddressGeocoder, call: Geo::AddressGeocoder::Result.new(latitude: -26.99, longitude: -48.63, display_name: "Rua", house_number: nil, provider: "osm", precision: "street"))
    allow(Geo::AddressGeocoder).to receive(:new).and_return(geocoder)

    described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id)

    expect(Geo::AddressGeocoder).to have_received(:new).with(hash_including(api_key: nil, provider: "leaflet"))
    expect(habitation.address.reload.latitude.to_f).to eq(-26.99)
  end

  describe "rua não encontrada" do
    let(:habitation) { create(:habitation, latitude: nil, longitude: nil) }
    let(:neighborhood) { Geo::AddressGeocoder::Result.new(latitude: -26.95, longitude: -48.62, display_name: "Praia Brava", house_number: nil, provider: "osm", precision: "neighborhood") }
    let(:street) { Geo::AddressGeocoder::Result.new(latitude: -26.96, longitude: -48.63, display_name: "Rua", house_number: "1", provider: "google", precision: "rooftop") }
    let(:geocoder) { instance_double(Geo::AddressGeocoder, call: nil, neighborhood_call: neighborhood) }

    before do
      allow(GoogleMapsIntegrationSetting).to receive(:for)
        .and_return(instance_double(GoogleMapsIntegrationSetting, configured?: true, provider: "leaflet", api_key: nil))
      allow(Geo::AddressGeocoder).to receive(:new).and_return(geocoder)
    end

    it "usa o centro do bairro marcado como aproximado e troca quando a rua for encontrada depois" do
      described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id)
      address = habitation.address.reload
      expect(address.latitude.to_f).to eq(-26.95)
      expect(address).to be_neighborhood_coordinates

      described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id)
      expect(geocoder).to have_received(:neighborhood_call).once

      allow(geocoder).to receive(:call).and_return(street)
      described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id)
      address.reload
      expect(address.latitude.to_f).to eq(-26.96)
      expect(address.coordinates_precision).to eq(Address::STREET_PRECISION)
    end
  end

  describe "endereço alterado (refresh)" do
    let(:habitation) { create(:habitation, latitude: nil, longitude: nil) }
    let(:new_street) { Geo::AddressGeocoder::Result.new(latitude: -27.1, longitude: -48.7, display_name: "Rua Nova", house_number: "9", provider: "osm", precision: "street") }

    before do
      allow(GoogleMapsIntegrationSetting).to receive(:for)
        .and_return(instance_double(GoogleMapsIntegrationSetting, configured?: true, provider: "leaflet", api_key: nil))
      habitation.address.update!(latitude: -26.9, longitude: -48.6, coordinates_precision: Address::STREET_PRECISION)
    end

    it "recalcula a coordenada automática para o novo endereço" do
      allow(Geo::AddressGeocoder).to receive(:new).and_return(instance_double(Geo::AddressGeocoder, call: new_street))

      described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id, refresh: true)

      expect(habitation.address.reload.latitude.to_f).to eq(-27.1)
      expect(habitation.address.coordinates_precision).to eq(Address::STREET_PRECISION)
    end

    it "sem resultado para o novo endereço, apaga a coordenada antiga em vez de apontar para o lugar errado" do
      allow(Geo::AddressGeocoder).to receive(:new).and_return(instance_double(Geo::AddressGeocoder, call: nil, neighborhood_call: nil))

      described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id, refresh: true)

      expect(habitation.address.reload.latitude).to be_nil
      expect(habitation.address.coordinates_precision).to be_nil
    end

    it "não mexe em coordenada do import ou ajustada à mão" do
      habitation.address.update!(latitude: -26.5, longitude: -48.5) # sem marca = manual
      allow(Geo::AddressGeocoder).to receive(:new)

      described_class.perform_now(habitation.id, tenant_id: habitation.tenant_id, refresh: true)

      expect(Geo::AddressGeocoder).not_to have_received(:new)
      expect(habitation.address.reload.latitude.to_f).to eq(-26.5)
    end
  end
end

RSpec.describe Address do
  include ActiveJob::TestHelper

  it "agenda a geocodificação ao mudar o endereço também com Leaflet" do
    habitation = create(:habitation, latitude: nil, longitude: nil)
    allow(GoogleMapsIntegrationSetting).to receive(:for)
      .and_return(instance_double(GoogleMapsIntegrationSetting, configured?: true, provider: "leaflet"))

    expect { habitation.address.update!(logradouro: "Rua Nova") }.to have_enqueued_job(HabitationGeocodeJob)
  end

  it "ponto ajustado à mão deixa de ser aproximado" do
    habitation = create(:habitation, latitude: nil, longitude: nil)
    habitation.address.update!(latitude: -26.95, longitude: -48.62, coordinates_precision: Address::NEIGHBORHOOD_PRECISION)

    habitation.address.update!(latitude: -26.97, longitude: -48.64)

    expect(habitation.address.reload.coordinates_precision).to be_nil
  end

  describe "ao mudar o endereço de um imóvel já mapeado" do
    let(:habitation) { create(:habitation, latitude: nil, longitude: nil) }

    before do
      allow(GoogleMapsIntegrationSetting).to receive(:for)
        .and_return(instance_double(GoogleMapsIntegrationSetting, configured?: true, provider: "leaflet"))
    end

    it "recalcula quando a coordenada foi calculada pelo sistema" do
      habitation.address.update!(latitude: -26.9, longitude: -48.6, coordinates_precision: Address::STREET_PRECISION)

      expect { habitation.address.update!(logradouro: "Rua Corrigida") }
        .to have_enqueued_job(HabitationGeocodeJob).with(habitation.id, tenant_id: habitation.tenant_id, refresh: true)
    end

    it "preserva coordenada do import ou ajustada à mão" do
      habitation.address.update!(latitude: -26.9, longitude: -48.6)

      expect { habitation.address.update!(logradouro: "Rua Corrigida") }.not_to have_enqueued_job(HabitationGeocodeJob)
    end
  end
end

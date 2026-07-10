require "rails_helper"

RSpec.describe PublicMaps::PropertyPresentation do
  let(:tenant) do
    Tenant.create!(
      name: "Maps #{SecureRandom.hex(4)}",
      slug: "maps-#{SecureRandom.hex(6)}"
    )
  end
  let(:property) do
    create(
      :habitation,
      tenant: tenant,
      address_attributes: {
        logradouro: "Avenida Brasil",
        numero: "1000",
        bairro: "Centro",
        cidade: "Balneário Camboriú",
        uf: "SC",
        latitude: -26.9906000,
        longitude: -48.6348000
      }
    )
  end
  let(:setting) do
    GoogleMapsIntegrationSetting.new(
      tenant: tenant,
      enabled: false,
      default_display_mode: "approximate",
      approximate_radius_meters: 220,
      default_zoom: 15,
      satellite_enabled: true,
      street_view_enabled: false,
      external_link_enabled: true
    )
  end

  it "ofusca as coordenadas no servidor e mantém o resultado estável" do
    first = described_class.new(property, setting: setting)
    second = described_class.new(property, setting: setting)

    expect(first).to be_visible
    expect(first).to be_approximate
    expect(first.center_coordinates).to eq(second.center_coordinates)
    expect(first.center_coordinates).not_to eq([-26.9906, -48.6348])
  end

  it "respeita a opção de ocultar o mapa no imóvel" do
    property.update!(public_map_display_mode: "hidden")

    expect(described_class.new(property, setting: setting)).not_to be_visible
  end

  it "expõe coordenadas exatas somente quando o modo exato está selecionado" do
    property.update!(public_map_display_mode: "exact")
    presentation = described_class.new(property, setting: setting)

    expect(presentation.center_coordinates).to eq([-26.9906, -48.6348])
    expect(presentation.radius_meters).to eq(0)
  end

  it "não libera vista da rua pelo padrão seguro" do
    expect(described_class.new(property, setting: setting)).not_to be_street_view_enabled
  end

  it "usa as coordenadas exatas para a vista da rua somente após liberação explícita" do
    property.update!(public_street_view_mode: "enabled")
    setting.street_view_enabled = true
    allow(setting).to receive(:configured?).and_return(true)
    allow(setting).to receive(:api_key).and_return("maps-key")
    presentation = described_class.new(property, setting: setting)

    expect(presentation).to be_street_view_enabled
    expect(presentation.street_view_coordinates).to eq([-26.9906, -48.6348])
    expect(presentation.center_coordinates).not_to eq(presentation.street_view_coordinates)
  end
end

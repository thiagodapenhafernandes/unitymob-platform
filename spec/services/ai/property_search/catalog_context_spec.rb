require "rails_helper"

RSpec.describe Ai::PropertySearch::CatalogContext do
  let(:tenant) { Tenant.create!(name: "Catálogo IA #{SecureRandom.hex(3)}", slug: "catalogo-ia-#{SecureRandom.hex(4)}") }
  let(:setting) { PropertySetting.instance(tenant: tenant) }

  before do
    setting.update!(
      ai_property_search_allowed_fields: %w[transaction_type property_type city neighborhood development developer_name price amenities],
      ai_property_search_result_fields: %w[property_code title price city development_name],
      ai_property_search_development_aliases_enabled: true
    )
  end

  it "monta um contexto seguro, tenant-scoped e com aliases úteis" do
    reservation = create(
      :habitation,
      tenant:,
      tipo: "Empreendimento",
      categoria: "Apartamento",
      codigo: "DEV-RESERVA",
      nome_empreendimento: "Reserva do Parque",
      construtora: "Cyrela",
      cidade: "Rio de Janeiro",
      bairro: "Barra da Tijuca",
      valor_venda_cents: 1_800_000_00,
      dormitorios_qtd: 3
    )
    reservation.address.update!(cidade: "Rio de Janeiro", bairro: "Barra da Tijuca")
    DevelopmentAlias.create!(tenant:, development: reservation, name: "Residencial Reserva")

    create(
      :habitation,
      tenant:,
      categoria: "Apartamento",
      codigo: "APT-1",
      cidade: "Itajaí",
      bairro: "Centro"
    ).tap { |record| record.address.update!(cidade: "Itajaí", bairro: "Centro") }

    other_tenant = Tenant.create!(name: "Outro catálogo #{SecureRandom.hex(3)}", slug: "outro-catalogo-#{SecureRandom.hex(4)}")
    create(:habitation, tenant: other_tenant, tipo: "Empreendimento", categoria: "Apartamento", codigo: "OUTRO-1", nome_empreendimento: "Outro Empreendimento")

    context = described_class.new(
      setting:,
      tenant:,
      text: "quero no reserva e em barra da tijuca",
      current_filters: { price_max: "1200000" }
    ).call

    expect(context.fetch(:tenant)).to include(id: tenant.id, language: setting.ai_property_search_language)
    expect(context.fetch(:current_filters)).to include("price_max" => 1_200_000.0)

    catalog = context.fetch(:catalog)
    expect(catalog.fetch(:property_types).map { |item| item.fetch(:name) }).to include("Apartamento")
    expect(catalog.fetch(:cities).map { |item| item.fetch(:name) }).to include("Itajaí")
    expect(catalog.fetch(:developments).map { |item| item.fetch(:name) }).to include("Reserva do Parque")

    reservation_payload = catalog.fetch(:developments).find { |item| item.fetch(:name) == "Reserva do Parque" }
    expect(reservation_payload.fetch(:aliases)).to include("Residencial Reserva")
    expect(reservation_payload).to include(
      developer_name: "Cyrela",
      city: "Rio de Janeiro",
      neighborhood: "Barra da Tijuca",
      property_type: "Apartamento"
    )
    expect(catalog.fetch(:developments).map { |item| item.fetch(:name) }).not_to include("Outro Empreendimento")
  end

  it "respeita os limites configuráveis sem exigir ajuste manual inicial" do
    setting.update!(
      ai_property_search_catalog_property_types_limit: 1,
      ai_property_search_catalog_cities_limit: 1,
      ai_property_search_catalog_neighborhoods_limit: 1,
      ai_property_search_catalog_developments_limit: 1,
      ai_property_search_catalog_feature_terms_limit: 1,
      ai_property_search_catalog_alias_names_limit: 1
    )

    first = create(:habitation, tenant:, tipo: "Empreendimento", categoria: "Apartamento", codigo: "DEV-A-#{SecureRandom.hex(2)}", nome_empreendimento: "Alpha", cidade: "Itajaí", bairro: "Centro")
    first.address.update!(cidade: "Itajaí", bairro: "Centro")
    create(:habitation, tenant:, tipo: "Empreendimento", categoria: "Casa", codigo: "DEV-B-#{SecureRandom.hex(2)}", nome_empreendimento: "Beta", cidade: "Balneário Camboriú", bairro: "Pioneiros")

    context = described_class.new(setting:, tenant:, text: "alpha", current_filters: {}).call
    catalog = context.fetch(:catalog)

    expect(catalog.fetch(:developments).map { |item| item.fetch(:name) }).to include("Alpha")
    expect(catalog.fetch(:developments).map { |item| item.fetch(:name) }).not_to include("Outro Empreendimento")
  end
end

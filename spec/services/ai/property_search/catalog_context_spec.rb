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

  it "inclui nomes de empreendimentos cadastrados nas unidades publicáveis" do
    create(
      :habitation,
      tenant:,
      tipo: "Unitário",
      categoria: "Apartamento",
      codigo: "UNIT-AQUALINA",
      nome_empreendimento: "Aqualina Residence"
    )

    context = described_class.new(setting:, tenant:, text: "Aqualina Residence", current_filters: {}).call

    names = context.fetch(:catalog).fetch(:developments).map { |item| item.fetch(:name) }
    expect(names).to include("Aqualina Residence")
  end

  it "inclui nomes de unidades por similaridade quando o termo tem pequena diferença de grafia" do
    create(
      :habitation,
      tenant:,
      tipo: "Unitário",
      categoria: "Apartamento",
      codigo: "UNIT-ACQUALINA",
      nome_empreendimento: "Acqualina Residence"
    )

    context = described_class.new(setting:, tenant:, text: "Aqualina Residence", current_filters: {}).call

    names = context.fetch(:catalog).fetch(:developments).map { |item| item.fetch(:name) }
    expect(names).to include("Acqualina Residence")
  end

  it "exclui empreendimentos não publicados e seus aliases do catálogo" do
    published = create(
      :habitation,
      tenant:,
      tipo: "Empreendimento",
      categoria: "Apartamento",
      codigo: "DEV-PUBLICADO",
      nome_empreendimento: "Residencial Public Catalogo"
    )
    DevelopmentAlias.create!(tenant:, development: published, name: "Alias Public Catalogo")
    hidden = create(
      :habitation,
      tenant:,
      tipo: "Empreendimento",
      categoria: "Apartamento",
      codigo: "DEV-OCULTO",
      nome_empreendimento: "Residencial Oculto Catalogo",
      exibir_no_site_flag: false
    )
    DevelopmentAlias.create!(tenant:, development: hidden, name: "Alias Oculto Catalogo")
    suspended = create(
      :habitation,
      tenant:,
      tipo: "Empreendimento",
      categoria: "Apartamento",
      codigo: "DEV-SUSPENSO",
      nome_empreendimento: "Residencial Suspenso Catalogo",
      status: "Suspenso",
      motivo_suspensao: "Venda pausada"
    )
    DevelopmentAlias.create!(tenant:, development: suspended, name: "Alias Suspenso Catalogo")

    matched = described_class.new(setting:, tenant:, text: "Residencial Catalogo", current_filters: {}).call
    matched_names = matched.fetch(:catalog).fetch(:developments).flat_map do |item|
      [item.fetch(:name), *item.fetch(:aliases, [])]
    end
    expect(matched_names).to include("Residencial Public Catalogo", "Alias Public Catalogo")
    expect(matched_names).not_to include(
      "Residencial Oculto Catalogo", "Alias Oculto Catalogo",
      "Residencial Suspenso Catalogo", "Alias Suspenso Catalogo"
    )

    fallback = described_class.new(setting:, tenant:, text: "xyz sem termo correspondente", current_filters: {}).call
    fallback_names = fallback.fetch(:catalog).fetch(:developments).flat_map do |item|
      [item.fetch(:name), *item.fetch(:aliases, [])]
    end
    expect(fallback_names).not_to include(
      "Residencial Oculto Catalogo", "Alias Oculto Catalogo",
      "Residencial Suspenso Catalogo", "Alias Suspenso Catalogo"
    )
  end
end

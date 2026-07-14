require "rails_helper"

RSpec.describe Ai::PropertySearch::SuggestionFinder do
  it "retorna alternativas somente depois de relaxar um critério controlado" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    setting = PropertySetting.instance(tenant: tenant)
    alternative = create(:habitation, tenant:, admin_user: broker, categoria: "Apartamento", dormitorios_qtd: 4, codigo: "SUGGESTION")

    result = described_class.new(
      tenant:, admin_user: broker, setting:,
      filters: { "property_type" => "Apartamento", "bedrooms_min" => 5 }
    ).call

    expect(result.records.map(&:id)).to include(alternative.id)
    expect(result.message).to include("flexibilizam")
    expect(result.filters["bedrooms_min"]).to eq(4)
  end

  it "mantém o tenant nas sugestões sem limitar o catálogo ao captador" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    other_broker = create(:admin_user, tenant: tenant)
    setting = PropertySetting.instance(tenant: tenant)
    catalog_property = create(:habitation, tenant:, admin_user: other_broker, categoria: "Apartamento", dormitorios_qtd: 4, codigo: "CATALOG-SUGGESTION")
    outside_tenant = Tenant.create!(name: "Outra sugestão IA #{SecureRandom.hex(3)}", slug: "outra-sugestao-ia-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: outside_tenant, categoria: "Apartamento", dormitorios_qtd: 4, codigo: "FORBIDDEN-SUGGESTION")

    result = described_class.new(
      tenant:, admin_user: broker, setting:,
      filters: { "property_type" => "Apartamento", "bedrooms_min" => 5 }
    ).call

    expect(result.records.map(&:id)).to include(catalog_property.id)
    expect(result.records.map(&:codigo)).not_to include("FORBIDDEN-SUGGESTION")
  end

  it "expõe quais critérios foram relaxados na sugestão" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    setting = PropertySetting.instance(tenant: tenant)
    create(:habitation, tenant:, admin_user: broker, categoria: "Apartamento", dormitorios_qtd: 4, codigo: "RELAXED-META")

    result = described_class.new(
      tenant:, admin_user: broker, setting:,
      filters: { "property_type" => "Apartamento", "bedrooms_min" => 5 }
    ).call

    expect(result.relaxed).to eq(%w[quantities])
  end

  it "flexibiliza o preço para mais no máximo e para menos no mínimo" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    setting = PropertySetting.instance(tenant: tenant)
    setting.update!(ai_property_search_price_tolerance_percentage: 10)
    expensive = create(:habitation, tenant:, admin_user: broker, categoria: "Apartamento", valor_venda_cents: 2_100_000_00, codigo: "PRICE-RANGE")

    result = described_class.new(
      tenant:, admin_user: broker, setting:,
      filters: { "property_type" => "Apartamento", "price_min" => 2_150_000, "price_max" => 2_050_000 }
    ).call

    expect(result.records.map(&:id)).to include(expensive.id)
    expect(result.relaxed).to eq(%w[price])
    expect(result.filters["price_max"].to_f).to be_within(0.01).of(2_255_000)
    expect(result.filters["price_min"].to_f).to be_within(0.01).of(1_935_000)
  end

  it "variante resiliente combina relaxamentos mantendo cidade, tipo e finalidade" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    setting = PropertySetting.instance(tenant: tenant)
    setting.update!(ai_property_search_allow_flexible_results: false, ai_property_search_resilient_search_enabled: true)
    match = create(:habitation, tenant:, admin_user: broker, categoria: "Apartamento", dormitorios_qtd: 3, cidade: "Cidade Resiliente", valor_venda_cents: 1_050_000_00, codigo: "RESILIENT-MATCH")
    match.address.update!(cidade: "Cidade Resiliente", bairro: "Bairro Real")
    other_city = create(:habitation, tenant:, admin_user: broker, categoria: "Apartamento", dormitorios_qtd: 4, cidade: "Outra Cidade", codigo: "RESILIENT-OTHER-CITY")
    other_city.address.update!(cidade: "Outra Cidade", bairro: "Bairro Real")

    result = described_class.new(
      tenant:, admin_user: broker, setting:,
      filters: {
        "property_type" => "Apartamento",
        "city" => "Cidade Resiliente",
        "neighborhood" => "Bairro Inexistente",
        "bedrooms_min" => 4,
        "price_max" => 1_000_000
      }
    ).call

    expect(result.records.map(&:id)).to include(match.id)
    expect(result.records.map(&:codigo)).not_to include("RESILIENT-OTHER-CITY")
    expect(result.relaxed).to match_array(%w[neighborhood quantities price])
    expect(result.filters["city"]).to eq("Cidade Resiliente")
    expect(result.filters["property_type"]).to eq("Apartamento")
  end

  it "não sugere nada quando os dois recursos estão desligados" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    setting = PropertySetting.instance(tenant: tenant)
    setting.update!(ai_property_search_allow_flexible_results: false, ai_property_search_resilient_search_enabled: false)
    create(:habitation, tenant:, admin_user: broker, categoria: "Apartamento", dormitorios_qtd: 4, codigo: "GATED-OFF")

    result = described_class.new(
      tenant:, admin_user: broker, setting:,
      filters: { "property_type" => "Apartamento", "bedrooms_min" => 5 }
    ).call

    expect(result.records).to be_empty
    expect(result.relaxed).to be_empty
  end
end

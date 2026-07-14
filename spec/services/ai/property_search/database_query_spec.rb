require "rails_helper"

RSpec.describe Ai::PropertySearch::DatabaseQuery do
  it "consulta o catálogo publicável do tenant, aplica filtros e limita o resultado" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    other_broker = create(:admin_user, tenant: tenant)
    setting = PropertySetting.instance(tenant: tenant)
    setting.update!(ai_property_search_enabled: true, ai_property_search_max_results: 1)
    own = create(:habitation, tenant: tenant, admin_user: broker, codigo: "AI-OWN", categoria: "Apartamento", dormitorios_qtd: 3, bairro: "Centro")
    create(:habitation, tenant: tenant, admin_user: broker, codigo: "AI-SECOND", categoria: "Apartamento", dormitorios_qtd: 4, bairro: "Centro")
    other = create(:habitation, tenant: tenant, admin_user: other_broker, codigo: "AI-OTHER", categoria: "Apartamento", dormitorios_qtd: 3, bairro: "Centro")
    create(:habitation, tenant: tenant, admin_user: broker, codigo: "AI-DRAFT", categoria: "Apartamento", exibir_no_site_flag: false)
    outside_tenant = Tenant.create!(name: "Outro catálogo IA #{SecureRandom.hex(3)}", slug: "outro-catalogo-ia-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: outside_tenant, codigo: "AI-OUTSIDE-TENANT", categoria: "Apartamento", dormitorios_qtd: 3, bairro: "Centro")

    result = described_class.new(
      tenant: tenant,
      admin_user: broker,
      setting: setting,
      filters: { property_type: "Apartamento", bedrooms_min: 3, neighborhood: "Centro" }
    ).call

    expect(result.records.size).to eq(1)
    expect(result.records.map(&:id)).to include(own.id).or include(other.id).or include(Habitation.find_by!(codigo: "AI-SECOND").id)
    expect(result.records.map(&:codigo)).not_to include("AI-DRAFT", "AI-OUTSIDE-TENANT")
  end

  it "não usa silenciosamente o banco para uma fonte sem adaptador autorizado" do
    setting = PropertySetting.instance
    setting.update!(ai_property_search_data_source: "external_api")

    expect {
      Ai::PropertySearch::DataSource.call(tenant: Tenant.default, admin_user: create(:admin_user), setting:, filters: {})
    }.to raise_error(Ai::PropertySearch::DataSource::UnsupportedSource)
  end

  it "consulta somente unidades do empreendimento resolvido no tenant" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant: tenant)
    setting = PropertySetting.instance(tenant: tenant)
    development = create(:habitation, tenant:, tipo: "Empreendimento", codigo: "DEV-TARGET", nome_empreendimento: "Reserva do Parque")
    target = create(:habitation, tenant:, admin_user: broker, codigo: "UNIT-TARGET", codigo_empreendimento: development.codigo, categoria: "Apartamento")
    create(:habitation, tenant:, admin_user: broker, codigo: "UNIT-OTHER", nome_empreendimento: "Reserva do Parque", categoria: "Apartamento")

    result = described_class.new(
      tenant:, admin_user: broker, setting:,
      filters: { "development_name" => "Reserva do Parque", "_development_codes" => [development.codigo] }
    ).call

    expect(result.records.map(&:id)).to eq([target.id])
  end

  it "usa a mesma regra estruturada de Frente Mar do catálogo" do
    tenant = Tenant.default
    broker = create(:admin_user, tenant:)
    setting = PropertySetting.instance(tenant:)
    setting.update!(ai_property_search_allowed_fields: (setting.ai_property_search_allowed_fields | ["amenities"]))
    matching = create(:habitation, tenant:, codigo: "AI-FRENTE-MAR", frente_mar_avenida_atlantica_flag: true, searchable_features: nil)
    create(:habitation, tenant:, codigo: "AI-VISTA-MAR", vista_frente_mar_flag: true, searchable_features: "vista mar")

    result = described_class.new(
      tenant:, admin_user: broker, setting:,
      filters: { "amenities" => ["Frente mar"] }
    ).call

    expect(result.records.map(&:id)).to include(matching.id)
    expect(result.records.map(&:codigo)).not_to include("AI-VISTA-MAR")
  end
end

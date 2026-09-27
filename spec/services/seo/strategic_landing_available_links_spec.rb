require "rails_helper"

RSpec.describe Seo::StrategicLanding do
  let(:tenant) { Tenant.create!(name: "Conta Teste", slug: "conta-#{SecureRandom.hex(3)}") }

  before { Rails.cache.clear }

  it "nas buscas relacionadas, mostra só links que levam a algum imóvel da conta" do
    create(:habitation, tenant:, exibir_no_site_flag: true, lancamento_flag: true, vista_frente_mar_flag: false, descricao_web: "Apartamento")

    labels = described_class.available_property_links(tenant:).map { _1[:label] }

    expect(labels).to include("Lançamentos")
    expect(labels).not_to include("Frente mar")
  end

  it "o link volta quando a conta passa a ter o imóvel" do
    create(:habitation, tenant:, exibir_no_site_flag: true, vista_frente_mar_flag: true)

    expect(described_class.available_property_links(tenant:).map { _1[:label] }).to include("Frente mar")
  end

  it "empreendimentos seguem a mesma regra" do
    development = create(:habitation, tenant:, tipo: "Empreendimento", lancamento_flag: true, vista_frente_mar_flag: false, descricao_web: "Torre")
    create(:habitation, tenant:, codigo_empreendimento: development.codigo)

    labels = described_class.available_development_links(tenant:).map { _1[:label] }

    expect(labels).to include("Lançamentos")
    expect(labels).not_to include("Frente mar")
  end
end

require "rails_helper"

RSpec.describe Tenant, type: :model do
  it "Salute resolve seu skin e nunca vê o da Conexão" do
    tenant = described_class.create!(name: "Salute Imóveis", slug: "salute-spec")

    expect(tenant.public_site_theme_key).to eq("saluteimoveis")
    expect(tenant.public_site_stylesheet).to eq("public_site_themes/saluteimoveis")
    expect(tenant.available_public_site_themes.keys).to contain_exactly("default", "saluteimoveis")
  end

  it "Conexão resolve seu skin e nunca vê o da Salute" do
    tenant = described_class.create!(name: "Conexão Imobiliária", slug: "conexao-spec")

    expect(tenant.public_site_theme_key).to eq("conexaoimobiliaria")
    expect(tenant.public_site_stylesheet).to eq("public_site_themes/conexaoimobiliaria")
    expect(tenant.available_public_site_themes.keys).to contain_exactly("default", "conexaoimobiliaria")
  end

  it "toda definição aponta para folha existente no disco" do
    described_class.public_site_theme_definitions.each do |key, config|
      path = Rails.root.join("app/assets/stylesheets/#{config[:stylesheet]}.css")
      expect(path.exist?).to be(true), "tema #{key} sem #{config[:stylesheet]}.css"
    end
  end
end

RSpec.describe Tenant, type: :model do
  it "Salute (slug salute) pode escolher o luxury" do
    tenant = described_class.create!(name: "Salute Imóveis", slug: "salute")

    expect(tenant.available_public_site_themes.keys).to include("salute_luxury")

    tenant.update!(public_site_theme: "salute_luxury")

    expect(tenant.public_site_stylesheet).to eq("public_site_themes/salute_luxury")
  end

  it "Conexão nunca vê o luxury" do
    tenant = described_class.create!(name: "Conexão Imobiliária", slug: "conexao")

    expect(tenant.available_public_site_themes.keys).not_to include("salute_luxury")
  end
end

RSpec.describe Tenant, type: :model do
  it "amarração por slug sobrevive a renomeação da conta (salute)" do
    tenant = described_class.create!(name: "Outro Nome", slug: "salute")

    expect(tenant.available_public_site_themes.keys).to contain_exactly("default", "saluteimoveis", "salute_luxury")
  end

  it "amarração por slug sobrevive a renomeação da conta (conexao)" do
    tenant = described_class.create!(name: "Outro Nome", slug: "conexao")

    expect(tenant.available_public_site_themes.keys).to contain_exactly("default", "conexaoimobiliaria")
  end
end

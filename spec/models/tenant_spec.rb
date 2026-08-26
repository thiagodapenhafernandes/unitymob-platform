require "rails_helper"

RSpec.describe Tenant, type: :model do
  it "cria os perfis verticais fixos Tenant Owner e Agent para toda nova conta" do
    tenant = described_class.create!(name: "Conta Governança #{SecureRandom.hex(3)}")

    owner = tenant.profiles.find_by!(key: "tenant_owner")
    agent = tenant.profiles.find_by!(key: "agent")

    expect(owner).to have_attributes(name: "Tenant Owner", axis: "vertical", position: 0, locked: true)
    expect(owner.permissions).to include("admin" => true)
    expect(agent).to have_attributes(name: "Agent", axis: "vertical", position: 10_000, locked: true)
  end

  it "mantem a criacao dos perfis fixos idempotente" do
    tenant = described_class.create!(name: "Conta Idempotente #{SecureRandom.hex(3)}")

    expect { tenant.ensure_builtin_profiles! }.not_to change { tenant.profiles.count }
  end

  it "cria um funil principal editável para contas novas" do
    tenant = described_class.create!(name: "Conta Funil #{SecureRandom.hex(3)}", slug: "conta-funil-#{SecureRandom.hex(3)}")

    pipeline = tenant.lead_pipelines.find_by!(name: "Principal")
    expect(pipeline).to have_attributes(
      kind: "mixed",
      active: true,
      default_general: true,
      default_for_sale: true,
      default_for_rental: true
    )
    expect(pipeline.stages.order(:position).pluck(:name)).to include("Novo Lead", "Em Atendimento")
  end

  it "resolve tenant publico por slug ativo e preserva default como fallback" do
    tenant = described_class.create!(name: "Conta Publica #{SecureRandom.hex(3)}", slug: "conta-publica-#{SecureRandom.hex(3)}")

    expect(described_class.public_for(slug: tenant.slug)).to eq(tenant)
    expect(described_class.public_for(slug: "inexistente")).to eq(described_class.default)
  end

  it "monta a URL base pública removendo o subdomínio app do domínio principal" do
    tenant = described_class.create!(name: "Conta Sitemap #{SecureRandom.hex(3)}", slug: "conta-sitemap-#{SecureRandom.hex(3)}")
    tenant.tenant_domains.create!(hostname: "app.conexaobc.com", primary_domain: true)

    expect(tenant.public_base_url(fallback_base_url: "https://app.conexaobc.com")).to eq("https://conexaobc.com")
  end

  it "usa o host da requisição sanitizado quando não há domínio público configurado" do
    tenant = described_class.create!(name: "Conta Fallback #{SecureRandom.hex(3)}", slug: "conta-fallback-#{SecureRandom.hex(3)}")

    expect(tenant.public_base_url(fallback_base_url: "https://app.tenant.test")).to eq("https://tenant.test")
  end

  it "resolve o tema publico implicitamente pela identidade da conta" do
    tenant = described_class.create!(name: "Conexão Imobiliária", slug: "conta-conexao-#{SecureRandom.hex(3)}")

    expect(tenant.public_site_theme_key).to eq("conexaoimobiliaria")
    expect(tenant.public_site_theme_label).to eq("Conexão Imobiliária")
    expect(tenant.public_site_stylesheet).to eq("public_site_themes/conexaoimobiliaria")
  end

  it "usa tema neutro como fallback quando a conta nao possui skin propria" do
    tenant = described_class.create!(name: "Conta Tema #{SecureRandom.hex(3)}")

    expect(tenant.public_site_theme_key).to eq("default")
    expect(tenant.public_site_stylesheet).to eq("public_site_themes/default")
  end
end

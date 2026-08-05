require "rails_helper"

RSpec.describe Tenants::DomainResolver do
  before do
    Tenants::LocalPublicHostOverride.clear!
  end

  after do
    Tenants::LocalPublicHostOverride.clear!
  end

  it "prefere domínio ativo ao fallback por slug" do
    default = Tenant.default
    by_slug = Tenant.create!(name: "Conta Slug #{SecureRandom.hex(3)}", slug: "conta-slug-#{SecureRandom.hex(3)}")
    by_domain = Tenant.create!(name: "Conta Host #{SecureRandom.hex(3)}", slug: "conta-host-#{SecureRandom.hex(3)}")
    domain = by_domain.tenant_domains.create!(hostname: "www.host.test", primary_domain: true)

    resolver = described_class.new(host: "www.host.test", slug: by_slug.slug)

    expect(resolver.tenant).to eq(by_domain)
    expect(resolver.matched_domain).to eq(domain)
    expect(resolver.tenant).not_to eq(default)
  end

  it "preserva fallback público atual quando o host não está cadastrado" do
    tenant = Tenant.create!(name: "Conta Fallback #{SecureRandom.hex(3)}", slug: "conta-fallback-#{SecureRandom.hex(3)}")

    expect(described_class.new(host: "nao-cadastrado.test", slug: tenant.slug).tenant).to eq(tenant)
    expect(described_class.new(host: "nao-cadastrado.test").tenant).to eq(Tenant.default)
  end

  it "usa override local para dev.unitymob.com.br sem depender de domínio da conta" do
    default = Tenant.default
    tenant = Tenant.create!(name: "Conexão Imobiliária", slug: "conexao-imobiliaria-#{SecureRandom.hex(3)}")

    Tenants::LocalPublicHostOverride.activate!(tenant)
    resolver = described_class.new(host: "dev.unitymob.com.br", slug: default.slug)

    expect(resolver.tenant).to eq(tenant)
    expect(resolver.matched_domain).to be_nil
  end
end

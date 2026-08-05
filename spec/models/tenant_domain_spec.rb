require "rails_helper"

RSpec.describe TenantDomain, type: :model do
  it "normaliza hostname removendo protocolo, porta e caminho" do
    tenant = Tenant.create!(name: "Conta Domínio #{SecureRandom.hex(3)}")
    domain = tenant.tenant_domains.create!(hostname: "https://WWW.Empresa.com.br:443/imoveis", ssl_mode: "shared_wildcard")

    expect(domain.hostname).to eq("www.empresa.com.br")
    expect(domain.ssl_mode_label).to eq("Wildcard compartilhado")
  end

  it "garante hostname único sem diferenciar maiúsculas" do
    tenant = Tenant.create!(name: "Conta Domínio A #{SecureRandom.hex(3)}")
    other = Tenant.create!(name: "Conta Domínio B #{SecureRandom.hex(3)}")

    tenant.tenant_domains.create!(hostname: "site.empresa.com.br")
    duplicate = other.tenant_domains.new(hostname: "SITE.Empresa.com.br")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:hostname]).to be_present
  end

  it "mantém apenas um domínio principal por tenant" do
    tenant = Tenant.create!(name: "Conta Principal #{SecureRandom.hex(3)}")
    first = tenant.tenant_domains.create!(hostname: "primeiro.empresa.com.br", primary_domain: true)
    second = tenant.tenant_domains.create!(hostname: "segundo.empresa.com.br", primary_domain: true)

    expect(first.reload).not_to be_primary_domain
    expect(second.reload).to be_primary_domain
  end

  it "resolve somente domínio ativo" do
    tenant = Tenant.create!(name: "Conta Resolve #{SecureRandom.hex(3)}")
    active = tenant.tenant_domains.create!(hostname: "ativo.empresa.com.br")
    tenant.tenant_domains.create!(hostname: "inativo.empresa.com.br", active: false)

    expect(described_class.find_for_host("http://ativo.empresa.com.br:3000")&.id).to eq(active.id)
    expect(described_class.find_for_host("inativo.empresa.com.br")).to be_nil
  end
end

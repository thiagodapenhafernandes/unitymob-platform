require "rails_helper"

RSpec.describe Tenants::PublicIdentity do
  it "consolida marca e contato sem atravessar tenants" do
    first = Tenant.create!(name: "Imobiliária Norte", slug: "norte-#{SecureRandom.hex(3)}")
    second = Tenant.create!(name: "Imobiliária Sul", slug: "sul-#{SecureRandom.hex(3)}")
    LayoutSetting.instance(tenant: first).update!(site_name: "Norte Imóveis")
    LayoutSetting.instance(tenant: second).update!(site_name: "Sul Imóveis")
    ContactSetting.instance(tenant: first).update!(email_primary: "norte@example.com", phone: "(11) 3333-1111")
    ContactSetting.instance(tenant: second).update!(email_primary: "sul@example.com", phone: "(48) 3333-2222")

    north = described_class.new(first)
    south = described_class.new(second)

    expect(north).to have_attributes(name: "Norte Imóveis", email: "norte@example.com", phone: "551133331111")
    expect(south).to have_attributes(name: "Sul Imóveis", email: "sul@example.com", phone: "554833332222")
  end

  it "calcula a cidade principal somente com imóveis públicos do tenant" do
    first = Tenant.create!(name: "Conta Curitiba", slug: "curitiba-#{SecureRandom.hex(3)}")
    second = Tenant.create!(name: "Conta Recife", slug: "recife-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: first, codigo: "CITY-#{SecureRandom.hex(5)}", cidade: "Curitiba", address_attributes: { logradouro: "Rua Norte", bairro: "Centro", cidade: "Curitiba", uf: "PR" }, exibir_no_site_flag: true)
    create(:habitation, tenant: second, codigo: "CITY-#{SecureRandom.hex(5)}", cidade: "Recife", address_attributes: { logradouro: "Rua Sul", bairro: "Centro", cidade: "Recife", uf: "PE" }, exibir_no_site_flag: true)

    expect(described_class.new(first).primary_city).to eq("Curitiba")
  end

  it "não cria identidade ou contatos da Salute em um tenant novo" do
    tenant = Tenant.create!(name: "Nova Operação", slug: "nova-operacao-#{SecureRandom.hex(3)}")

    identity = described_class.new(tenant)

    expect(identity.name).to eq("Nova Operação")
    expect(identity.email).to be_blank
    expect(identity.phone).to be_blank
    expect(FooterSetting.instance(tenant: tenant).about_title).to eq("Nova Operação")
    expect(FooterSetting.instance(tenant: tenant).about_text).not_to match(/Salute|Balneário Camboriú/i)
  end
end

require "rails_helper"

RSpec.describe Habitation, "tenant uniqueness", type: :model do
  it "permite mesmo codigo em tenants diferentes e bloqueia duplicidade dentro do mesmo Tenant" do
    tenant_a = Tenant.create!(name: "Tenant hab #{SecureRandom.hex(3)}", slug: "tenant-hab-#{SecureRandom.hex(3)}")
    tenant_b = Tenant.create!(name: "Outro hab #{SecureRandom.hex(3)}", slug: "outro-hab-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: tenant_a, codigo: "HAB-TENANT-1")

    same_code_other_tenant = build(:habitation, tenant: tenant_b, codigo: "HAB-TENANT-1")
    duplicate_same_tenant = build(:habitation, tenant: tenant_a, codigo: "HAB-TENANT-1")

    expect(same_code_other_tenant).to be_valid
    expect(duplicate_same_tenant).not_to be_valid
    expect(duplicate_same_tenant.errors[:codigo]).to be_present
  end

  it "valida codigo_empreendimento somente dentro do mesmo tenant" do
    tenant_a = Tenant.create!(name: "Tenant hab #{SecureRandom.hex(3)}", slug: "tenant-hab-#{SecureRandom.hex(3)}")
    tenant_b = Tenant.create!(name: "Outro hab #{SecureRandom.hex(3)}", slug: "outro-hab-#{SecureRandom.hex(3)}")
    create(
      :habitation,
      tenant: tenant_b,
      codigo: "DEV-TENANT-1",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento de outro tenant"
    )

    unit = build(
      :habitation,
      tenant: tenant_a,
      codigo: "UNIT-TENANT-1",
      categoria: "Apartamento",
      tipo: "Unitário",
      codigo_empreendimento: "DEV-TENANT-1",
      nome_empreendimento: "Nome local",
      address_attributes: { logradouro: "Rua 100", numero: "10", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
    )

    expect(unit).not_to be_valid
    expect(unit.errors[:codigo_empreendimento]).to be_present
    expect(unit.nome_empreendimento).to eq("Nome local")
  end

  it "sincroniza dados da unidade a partir do empreendimento do mesmo tenant" do
    tenant = Tenant.create!(name: "Tenant hab #{SecureRandom.hex(3)}", slug: "tenant-hab-#{SecureRandom.hex(3)}")
    create(
      :habitation,
      tenant: tenant,
      codigo: "DEV-TENANT-2",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento local"
    )

    unit = build(
      :habitation,
      tenant: tenant,
      codigo: "UNIT-TENANT-2",
      categoria: "Apartamento",
      tipo: "Unitário",
      codigo_empreendimento: "DEV-TENANT-2",
      nome_empreendimento: "Nome antigo",
      address_attributes: { logradouro: "Rua 200", numero: "20", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
    )

    expect(unit).to be_valid
    expect(unit.nome_empreendimento).to eq("Empreendimento local")
  end

  it "conta unidades disponíveis do empreendimento somente no mesmo tenant" do
    tenant_a = Tenant.create!(name: "Tenant hab #{SecureRandom.hex(3)}", slug: "tenant-hab-#{SecureRandom.hex(3)}")
    tenant_b = Tenant.create!(name: "Outro hab #{SecureRandom.hex(3)}", slug: "outro-hab-#{SecureRandom.hex(3)}")
    development_a = create(
      :habitation,
      tenant: tenant_a,
      codigo: "DEV-TENANT-3",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento A"
    )
    development_b = create(
      :habitation,
      tenant: tenant_b,
      codigo: "DEV-TENANT-3",
      categoria: "Empreendimento",
      tipo: "Empreendimento",
      nome_empreendimento: "Empreendimento B"
    )
    create(
      :habitation,
      tenant: tenant_b,
      codigo: "UNIT-TENANT-3B",
      categoria: "Apartamento",
      tipo: "Unitário",
      codigo_empreendimento: development_b.codigo,
      address_attributes: { logradouro: "Rua 300", numero: "30", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
    )

    expect(tenant_a.habitations.where(id: development_a.id).with_available_units).to be_empty

    create(
      :habitation,
      tenant: tenant_a,
      codigo: "UNIT-TENANT-3A",
      categoria: "Apartamento",
      tipo: "Unitário",
      codigo_empreendimento: development_a.codigo,
      address_attributes: { logradouro: "Rua 400", numero: "40", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" }
    )

    expect(tenant_a.habitations.where(id: development_a.id).with_available_units).to include(development_a)
  end
end

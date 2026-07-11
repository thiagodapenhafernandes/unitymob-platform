require "rails_helper"

RSpec.describe Habitations::InvalidParentReconciliationService do
  it "não usa empreendimento de outro tenant como sugestão de pai" do
    current_tenant = Tenant.create!(name: "Tenant parent #{SecureRandom.hex(3)}", slug: "tenant-parent-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro parent #{SecureRandom.hex(3)}", slug: "outro-parent-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: other_tenant, codigo: "DEV-OUT", tipo: "Empreendimento", categoria: "Empreendimento", nome_empreendimento: "Residencial Externo")
    unit = build(:habitation, tenant: current_tenant, codigo: "UNIT-CUR", codigo_empreendimento: "DEV-OUT", nome_empreendimento: "Residencial Externo")
    unit.save!(validate: false)

    result = described_class.new(tenant: current_tenant).call

    expect(result.invalid_total).to eq(1)
    expect(result.unresolved).to eq(1)
    expect(result.rows.first).to include(unit_id: unit.id, suggested_parent_id: nil)
  end

  it "consulta por código somente os possíveis pais inválidos" do
    tenant = Tenant.create!(name: "Tenant scoped #{SecureRandom.hex(3)}", slug: "tenant-scoped-#{SecureRandom.hex(3)}")
    candidate = build(:habitation, tenant: tenant, codigo: "DEV-TARGET", categoria: "Empreendimento")
    candidate.save!(validate: false)
    irrelevant = build(:habitation, tenant: tenant, codigo: "DEV-IRRELEVANT", categoria: "Empreendimento")
    irrelevant.save!(validate: false)
    unit = build(:habitation, tenant: tenant, codigo: "UNIT", codigo_empreendimento: "DEV-TARGET")
    unit.save!(validate: false)

    service = described_class.new(tenant: tenant)

    loaded_codes = service.instance_variable_get(:@any_habitation_by_code).keys
    expect(loaded_codes).to eq(["DEV-TARGET"])
  end
end

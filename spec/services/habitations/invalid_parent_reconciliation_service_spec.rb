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
end

require "rails_helper"

RSpec.describe Habitations::InvalidParentVistaBackfillService do
  it "calcula pais inválidos apenas contra empreendimentos do tenant atual" do
    current_tenant = Tenant.create!(name: "Tenant vista parent #{SecureRandom.hex(3)}", slug: "tenant-vista-parent-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro vista parent #{SecureRandom.hex(3)}", slug: "outro-vista-parent-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: other_tenant, codigo: "DEV-VISTA", tipo: "Empreendimento", categoria: "Empreendimento")
    unit = build(:habitation, tenant: current_tenant, codigo: "UNIT-VISTA", codigo_empreendimento: "DEV-VISTA")
    unit.save!(validate: false)

    service = described_class.new(tenant: current_tenant)

    expect(service.send(:invalid_parent_codes)).to eq(["DEV-VISTA"])
  end
end

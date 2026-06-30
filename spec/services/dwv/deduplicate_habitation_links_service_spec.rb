require "rails_helper"

RSpec.describe Dwv::DeduplicateHabitationLinksService do
  it "não trata código DWV igual em outro tenant como duplicidade" do
    current_tenant = Tenant.create!(name: "Tenant dedup DWV #{SecureRandom.hex(3)}", slug: "tenant-dedup-dwv-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro dedup DWV #{SecureRandom.hex(3)}", slug: "outro-dedup-dwv-#{SecureRandom.hex(3)}")

    current_tenant_habitation = create(:habitation, tenant: current_tenant, codigo: "CUR-DWV-1", codigo_dwv: "DWV-1", imovel_dwv: "Sim")
    other_tenant_habitation = create(:habitation, tenant: other_tenant, codigo: "OUT-DWV-1", codigo_dwv: "DWV-1", imovel_dwv: "Sim")

    result = described_class.new(tenant: current_tenant).call!

    expect(result).to include(duplicate_groups: 0, detached: 0)
    expect(current_tenant_habitation.reload).to have_attributes(codigo_dwv: "DWV-1", imovel_dwv: "Sim")
    expect(other_tenant_habitation.reload).to have_attributes(codigo_dwv: "DWV-1", imovel_dwv: "Sim")
  end
end

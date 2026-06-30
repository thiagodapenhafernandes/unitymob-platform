require "rails_helper"

RSpec.describe Loft::ImagesSyncService do
  it "processa apenas imóveis do tenant informado" do
    current_tenant = Tenant.create!(name: "Tenant loft images #{SecureRandom.hex(3)}", slug: "tenant-loft-images-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro loft images #{SecureRandom.hex(3)}", slug: "outro-loft-images-#{SecureRandom.hex(3)}")
    create(:habitation, tenant: current_tenant, codigo: "CUR-IMG", imovel_dwv: "Nao", pictures: [])
    create(:habitation, tenant: other_tenant, codigo: "OUT-IMG", imovel_dwv: "Nao", pictures: [])

    result = described_class.new(tenant: current_tenant).call(limit: 10)

    expect(result).to include(processed: 1, synced: 0, skipped: 1, failed: 0)
  end
end

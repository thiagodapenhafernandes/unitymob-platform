require "rails_helper"

RSpec.describe StorageIntegrationSetting, type: :model do
  it "gera nomes de serviço Active Storage distintos por tenant" do
    tenant_a = Tenant.create!(name: "Storage A", slug: "storage-a-#{SecureRandom.hex(3)}")
    tenant_b = Tenant.create!(name: "Storage B", slug: "storage-b-#{SecureRandom.hex(3)}")
    setting_a = described_class.new(tenant: tenant_a, photo_provider: "digital_ocean")
    setting_b = described_class.new(tenant: tenant_b, photo_provider: "digital_ocean")

    expect(setting_a.photo_service_name).to eq("do_spaces_db_tenant_#{tenant_a.id}".to_sym)
    expect(setting_b.photo_service_name).to eq("do_spaces_db_tenant_#{tenant_b.id}".to_sym)
    expect(setting_a.photo_service_name).not_to eq(setting_b.photo_service_name)
  end
end

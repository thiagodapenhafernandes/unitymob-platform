require "rails_helper"

RSpec.describe PublicNavigationSession, type: :model do
  it "não reaproveita token de navegação entre tenants diferentes" do
    first_tenant = Tenant.create!(name: "Site A #{SecureRandom.hex(3)}", slug: "site-a-#{SecureRandom.hex(3)}")
    second_tenant = Tenant.create!(name: "Site B #{SecureRandom.hex(3)}", slug: "site-b-#{SecureRandom.hex(3)}")
    request = instance_double(ActionDispatch::Request, user_agent: "RSpec", remote_ip: "127.0.0.1", referer: "https://site.test/", original_url: "https://site.test/imoveis")
    original = described_class.create!(tenant: first_tenant, token: "shared-token")

    created = described_class.find_or_create_for_token("shared-token", request: request, tenant: second_tenant)

    expect(created).to be_persisted
    expect(created).not_to eq(original)
    expect(created.token).not_to eq("shared-token")
    expect(created.tenant).to eq(second_tenant)
  end
end

require "rails_helper"

RSpec.describe DataExportAuditLog, type: :model do
  it "não usa nome de admin_user de outro Tenant no actor_name" do
    tenant = Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: profile, name: "Usuário Externo")
    log = build(:data_export_audit_log, tenant: tenant, admin_user_id: other_user.id)

    expect(log.actor_name).to eq("Usuário não identificado")
  end
end

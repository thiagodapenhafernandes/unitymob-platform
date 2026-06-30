require "rails_helper"

RSpec.describe TrustedDevice, type: :model do
  it "permite dispositivo de plataforma para Admin do Sistema sem tenant" do
    system_admin = create(:admin_user, super_admin: true)

    device = described_class.create!(
      admin_user: system_admin,
      tenant: nil,
      fingerprint: "platform-#{SecureRandom.uuid}",
      name: "Dispositivo de plataforma"
    )

    expect(device).to be_persisted
    expect(device.tenant_id).to be_nil
  end

  it "preenche tenant pelo usuário da conta" do
    user = create(:admin_user)
    device = described_class.new(
      admin_user: user,
      tenant: nil,
      fingerprint: "account-#{SecureRandom.uuid}",
      name: "Dispositivo de conta"
    )

    expect(device).to be_valid
    expect(device.tenant).to eq(user.tenant)
  end

  it "bloqueia no banco dispositivo de plataforma vinculado a tenant" do
    system_admin = create(:admin_user, super_admin: true)

    expect {
      described_class.insert_all!([
        {
          admin_user_id: system_admin.id,
          tenant_id: Tenant.default.id,
          fingerprint: "invalid-platform-#{SecureRandom.uuid}",
          status: "pending",
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco dispositivo de usuário da conta sem tenant" do
    user = create(:admin_user)

    expect {
      described_class.insert_all!([
        {
          admin_user_id: user.id,
          fingerprint: "invalid-account-#{SecureRandom.uuid}",
          status: "pending",
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end
end

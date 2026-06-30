require "rails_helper"

RSpec.describe AdminUser, "Admin do Sistema", type: :model do
  it "system_admin? reflete a flag super_admin" do
    expect(build(:admin_user, super_admin: true).system_admin?).to be(true)
    expect(build(:admin_user, super_admin: false).system_admin?).to be(false)
  end

  it "super_admin não é admin da conta" do
    user = build(:admin_user, role: :editor, profile: nil, super_admin: true)
    expect(user.system_admin?).to be(true)
    expect(user.admin?).to be(false)
  end

  it "mantém Admin do Sistema fora de tenant, perfil, função horizontal e hierarquia" do
    tenant = Tenant.default
    profile = tenant.profiles.find_by!(key: "agent")
    user = create(:admin_user, super_admin: true, tenant: tenant, profile: profile)

    expect(user).to be_system_admin
    expect(user.tenant).to be_nil
    expect(user.profile).to be_nil
    expect(user.horizontal_profile).to be_nil
    expect(user.manager).to be_nil
  end

  it "usuário comum (sem flags) não é admin nem system_admin" do
    user = build(:admin_user, role: :editor, profile: nil, super_admin: false)
    expect(user.admin?).to be_falsey
    expect(user.system_admin?).to be(false)
  end

  it "operador (super_admin) fica fora das listas da conta" do
    member = create(:admin_user, super_admin: false, active: true)
    op     = create(:admin_user, super_admin: true, active: true)

    expect(AdminUser.account_members).to include(member)
    expect(AdminUser.account_members).not_to include(op)
    expect(AdminUser.active).not_to include(op)        # some dos dropdowns .active
    expect(AdminUser.displayed_on_site).not_to include(op)
  end

  it "bloqueia no banco usuário de conta sem tenant" do
    expect {
      described_class.insert_all!([
        {
          email: "sem-tenant-#{SecureRandom.hex(4)}@example.test",
          encrypted_password: "x",
          name: "Sem Tenant",
          role: AdminUser.roles[:editor],
          acting_type: AdminUser.acting_types[:both],
          active: true,
          super_admin: false,
          require_ip_allowlist: false,
          require_trusted_device: false,
          display_on_site: true,
          field_agent_enabled: false,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco Admin do Sistema vinculado a tenant ou perfil de conta" do
    tenant = Tenant.default
    profile = tenant.profiles.find_by!(key: "agent")

    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          profile_id: profile.id,
          email: "sistema-com-tenant-#{SecureRandom.hex(4)}@example.test",
          encrypted_password: "x",
          name: "Sistema com Tenant",
          role: AdminUser.roles[:editor],
          acting_type: AdminUser.acting_types[:both],
          active: true,
          super_admin: true,
          require_ip_allowlist: false,
          require_trusted_device: false,
          display_on_site: true,
          field_agent_enabled: false,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end
end

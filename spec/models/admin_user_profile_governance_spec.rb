require "rails_helper"

RSpec.describe AdminUser, "perfis vertical e horizontal", type: :model do
  let(:tenant) { Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}") }

  it "combina permissões verticais e horizontais sem ampliar escopo acima do vertical" do
    vertical = Profile.create!(
      tenant: tenant,
      name: "Manager",
      axis: "vertical",
      position: 200,
      permissions: {
        "leads" => { "view" => true, "scope" => "team" }
      }
    )
    horizontal = Profile.create!(
      tenant: tenant,
      name: "Marketing",
      axis: "horizontal",
      vertical_profile: vertical,
      permissions: {
        "marketing" => { "manage" => true },
        "leads" => { "view" => true, "scope" => "all" }
      }
    )

    user = build(:admin_user, tenant: tenant, profile: vertical, horizontal_profile: horizontal)

    expect(user.can?(:view, :leads)).to be(true)
    expect(user.can?(:manage, :marketing)).to be(true)
    expect(user.scope_for(:leads)).to eq("team")
  end

  it "permite que a função horizontal restrinja escopo sem conceder nova ação" do
    vertical = Profile.create!(
      tenant: tenant,
      name: "Director",
      axis: "vertical",
      position: 150,
      permissions: {
        "leads" => { "view" => true, "manage" => true, "scope" => "all" }
      }
    )
    horizontal = Profile.create!(
      tenant: tenant,
      name: "Auditor Restrito",
      axis: "horizontal",
      vertical_profile: vertical,
      permissions: {
        "leads" => { "scope" => "team" }
      }
    )

    user = build(:admin_user, tenant: tenant, profile: vertical, horizontal_profile: horizontal)

    expect(user.can?(:manage, :leads)).to be(true)
    expect(user.scope_for(:leads)).to eq("team")
  end

  it "bloqueia função horizontal anexada a outro perfil vertical" do
    manager = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    director = Profile.create!(tenant: tenant, name: "Director", axis: "vertical", position: 150, permissions: {})
    support = Profile.create!(tenant: tenant, name: "Support", axis: "horizontal", vertical_profile: director, permissions: {})

    user = build(:admin_user, tenant: tenant, profile: manager, horizontal_profile: support)

    expect(user).not_to be_valid
    expect(user.errors[:horizontal_profile]).to be_present
  end

  it "não permite gestor de outro Tenant" do
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    manager = create(:admin_user, tenant: other_tenant)
    user = build(:admin_user, tenant: tenant, manager: manager)

    expect(user).not_to be_valid
    expect(user.errors[:manager]).to be_present
  end

  it "bloqueia no banco gestor de outro Tenant" do
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    manager_profile = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    other_profile = Profile.create!(tenant: other_tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    manager = create(:admin_user, tenant: tenant, profile: manager_profile)
    other_user = create(:admin_user, tenant: other_tenant, profile: other_profile)

    expect {
      other_user.update_columns(manager_id: manager.id)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "exige que o gestor esteja acima no eixo vertical" do
    director = Profile.create!(tenant: tenant, name: "Director", axis: "vertical", position: 150, permissions: {})
    manager_profile = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 300, permissions: {})
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile)

    valid_user = build(:admin_user, tenant: tenant, profile: agent_profile, manager: manager)
    invalid_user = build(:admin_user, tenant: tenant, profile: director, manager: manager)

    expect(valid_user).to be_valid
    expect(invalid_user).not_to be_valid
    expect(invalid_user.errors[:manager]).to be_present
  end

  it "compara autoridade pela posição do perfil vertical, não pelo nome do cargo" do
    superintendent = Profile.create!(tenant: tenant, name: "Superintendent", axis: "vertical", position: 150, permissions: {})
    coordinator = Profile.create!(tenant: tenant, name: "Coordinator", axis: "vertical", position: 600, permissions: {})
    upper_user = create(:admin_user, tenant: tenant, profile: superintendent)
    lower_user = create(:admin_user, tenant: tenant, profile: coordinator)

    expect(upper_user.vertical_above?(lower_user)).to be(true)
    expect(lower_user.vertical_above?(upper_user)).to be(false)
    expect(upper_user.manager_candidate_for?(lower_user)).to be(true)
  end

  it "bloqueia no banco perfis verticais ou horizontais de outro Tenant no usuário" do
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    local_vertical = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    other_vertical = Profile.create!(tenant: other_tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    other_horizontal = Profile.create!(tenant: other_tenant, name: "Support", axis: "horizontal", vertical_profile: other_vertical, permissions: {})
    user = create(:admin_user, tenant: tenant, profile: local_vertical)

    expect {
      user.update_columns(profile_id: other_vertical.id, horizontal_profile_id: other_horizontal.id)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco associações de perfil cruzadas entre Tenants" do
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    vertical = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    other_vertical = Profile.create!(tenant: other_tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    other_horizontal = Profile.create!(tenant: other_tenant, name: "Support", axis: "horizontal", vertical_profile: other_vertical, permissions: {})
    other_user = create(:admin_user, tenant: other_tenant, profile: other_vertical)

    expect {
      other_horizontal.update_columns(vertical_profile_id: vertical.id)
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect {
      other_user.update_columns(profile_id: vertical.id)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco perfil vertical pai de outro Tenant em função horizontal" do
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    local_vertical = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    other_vertical = Profile.create!(tenant: other_tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    horizontal = Profile.create!(tenant: tenant, name: "Support", axis: "horizontal", vertical_profile: local_vertical, permissions: {})

    expect {
      horizontal.update_columns(vertical_profile_id: other_vertical.id)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "não trata role admin legado como autoridade sem perfil Tenant Owner" do
    manager_profile = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 300, permissions: { "admin" => true })
    user = build(:admin_user, tenant: tenant, profile: manager_profile, role: :admin)

    expect(user).not_to be_valid
    expect(user.errors[:role]).to be_present
    expect(user.admin?).to be(false)
    expect(user.can_manage_profiles?).to be(false)
  end

  it "atribui Agent como perfil vertical padrão para usuário operacional sem perfil explícito" do
    administrative_profile = tenant.profiles.find_by!(key: "administrativo")
    agent_profile = tenant.profiles.find_by!(key: "agent")

    user = described_class.create!(
      tenant: tenant,
      email: "agent-default-#{SecureRandom.hex(4)}@example.test",
      password: "password123",
      password_confirmation: "password123",
      name: "Usuário Padrão",
      role: :editor
    )

    expect(user.profile).to eq(agent_profile)
    expect(user.profile).not_to eq(administrative_profile)
  end

  it "atribui Tenant Owner como perfil vertical padrão somente para role admin legado" do
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")

    user = described_class.create!(
      tenant: tenant,
      email: "owner-default-#{SecureRandom.hex(4)}@example.test",
      password: "password123",
      password_confirmation: "password123",
      name: "Owner Padrão",
      role: :admin
    )

    expect(user.profile).to eq(owner_profile)
    expect(user).to be_tenant_owner
  end

  it "bloqueia no banco usuário de conta sem perfil vertical" do
    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          email: "sem-perfil-#{SecureRandom.hex(4)}@example.test",
          encrypted_password: "x",
          name: "Sem Perfil",
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

  it "bloqueia no banco profile_id apontando para função horizontal" do
    vertical = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 300, permissions: {})
    horizontal = Profile.create!(tenant: tenant, name: "Support", axis: "horizontal", vertical_profile: vertical, permissions: {})

    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          profile_id: horizontal.id,
          email: "perfil-horizontal-#{SecureRandom.hex(4)}@example.test",
          encrypted_password: "x",
          name: "Perfil Horizontal",
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

  it "bloqueia no banco função horizontal incompatível com o perfil vertical do usuário" do
    manager_profile = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 300, permissions: {})
    agent_profile = tenant.profiles.find_by!(key: "agent")
    support = Profile.create!(tenant: tenant, name: "Support", axis: "horizontal", vertical_profile: manager_profile, permissions: {})
    user = create(:admin_user, tenant: tenant, profile: agent_profile)

    expect {
      user.update_columns(horizontal_profile_id: support.id)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco gestor que não está acima no eixo vertical" do
    manager_profile = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 300, permissions: {})
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile)
    user = create(:admin_user, tenant: tenant, profile: manager_profile)
    lower_user = create(:admin_user, tenant: tenant, profile: agent_profile)

    expect {
      user.update_columns(manager_id: manager.id)
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect {
      manager.update_columns(manager_id: lower_user.id)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco ciclos na hierarquia de gestores" do
    director_profile = Profile.create!(tenant: tenant, name: "Director", axis: "vertical", position: 200, permissions: {})
    manager_profile = Profile.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 300, permissions: {})
    agent_profile = tenant.profiles.find_by!(key: "agent")
    director = create(:admin_user, tenant: tenant, profile: director_profile)
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: director)
    agent = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager)

    expect {
      director.update_columns(manager_id: agent.id)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "permite perfil horizontal de acesso total ampliar ações sem ultrapassar o escopo vertical" do
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Manager",
      axis: "vertical",
      position: 300,
      permissions: { "whatsapp_campaigns" => { "view" => true, "scope" => "team" } }
    )
    support_profile = Profile.create!(
      tenant: tenant,
      name: "Support",
      axis: "horizontal",
      vertical_profile: manager_profile,
      permissions: { "admin" => true }
    )
    user = build(:admin_user, tenant: tenant, profile: manager_profile, horizontal_profile: support_profile)

    expect(user.admin?).to be(false)
    expect(user.can_manage_profiles?).to be(false)
    expect(user.can?(:manage, :whatsapp_campaigns)).to be(true)
    expect(user.can?(:manage, :integracoes)).to be(true)
    expect(user.scope_for(:whatsapp_campaigns)).to eq("team")
  end

  it "impede rebaixar ou inativar o último Tenant Owner ativo do Tenant" do
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, active: true)

    expect(owner.update(profile: agent_profile)).to be(false)
    expect(owner.errors[:base]).to be_present

    owner.reload
    expect(owner.update(active: false)).to be(false)
    expect(owner.errors[:base]).to be_present
  end

  it "permite rebaixar Tenant Owner quando outro Tenant Owner ativo permanece" do
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, active: true)
    create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, active: true)

    expect(owner.update(profile: agent_profile)).to be(true)
  end
end

require "rails_helper"

RSpec.describe "Admin user governance", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  def create_vertical_profile(tenant, name, position, permissions = {})
    Profile.create!(
      tenant: tenant,
      name: name,
      axis: "vertical",
      position: position,
      permissions: permissions
    )
  end

  it "limita a gestao de usuarios com permissao de corretores a propria subarvore" do
    tenant = Tenant.create!(name: "Tenant usuarios #{SecureRandom.hex(3)}", slug: "tenant-usuarios-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    manager_profile = create_vertical_profile(tenant, "Manager", 300, "corretores" => { "manage" => true })
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, name: "Owner")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner, name: "Manager")
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager, name: "Subordinado")
    outside = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Fora")

    sign_in manager

    get admin_admin_users_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Subordinado")
    expect(response.body).not_to include("Fora")

    get edit_admin_admin_user_path(subordinate)
    expect(response).to have_http_status(:ok)

    get edit_admin_admin_user_path(outside)
    expect(response).to redirect_to(admin_admin_users_path)
  end

  it "impede gestor de atribuir perfil vertical acima ou gestor fora do proprio escopo" do
    tenant = Tenant.create!(name: "Tenant usuarios #{SecureRandom.hex(3)}", slug: "tenant-usuarios-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    director_profile = create_vertical_profile(tenant, "Director", 150, {})
    manager_profile = create_vertical_profile(tenant, "Manager", 300, "corretores" => { "manage" => true })
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, name: "Owner")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner, name: "Manager")
    outside_director = create(:admin_user, tenant: tenant, profile: director_profile, manager: owner, name: "Director Fora")
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager, name: "Subordinado")

    sign_in manager

    patch admin_admin_user_path(subordinate), params: {
      admin_user: {
        name: subordinate.name,
        email: subordinate.email,
        profile_id: director_profile.id,
        manager_id: outside_director.id,
        acting_type: subordinate.acting_type,
        active: "1"
      }
    }

    expect(response).to redirect_to(admin_admin_users_path)
    subordinate.reload
    expect(subordinate.profile).to eq(agent_profile)
    expect(subordinate.manager).to eq(manager)
  end

  it "mostra no cadastro apenas perfis abaixo do gestor logado" do
    tenant = Tenant.create!(name: "Tenant usuarios #{SecureRandom.hex(3)}", slug: "tenant-usuarios-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    director_profile = create_vertical_profile(tenant, "Director", 150, {})
    manager_profile = create_vertical_profile(tenant, "Manager", 300, "corretores" => { "manage" => true })
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor)
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner)

    sign_in manager

    get new_admin_admin_user_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(agent_profile.name)
    expect(response.body).not_to include(director_profile.name)
    expect(response.body).not_to include(owner_profile.name)
  end

  it "marca funções horizontais com o perfil vertical vinculado no formulário" do
    tenant = Tenant.create!(name: "Tenant horizontal #{SecureRandom.hex(3)}", slug: "tenant-horizontal-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    manager_profile = create_vertical_profile(tenant, "Manager", 300, "corretores" => { "manage" => true })
    support = Profile.create!(
      tenant: tenant,
      name: "Support",
      axis: "horizontal",
      vertical_profile: manager_profile,
      active: true,
      permissions: { "leads" => { "view" => true, "scope" => "team" } }
    )
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor)

    sign_in owner

    get new_admin_admin_user_path

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    option = doc.at_css(%(option[value="#{support.id}"]))
    expect(option).to be_present
    expect(option["data-vertical-profile-id"]).to eq(manager_profile.id.to_s)
    expect(response.body).to include('data-controller="admin-user-access"')
    expect(response.body).not_to include("admin_user_super_admin")
  end

  it "ignora tentativa de promover usuário da conta para Admin do Sistema pelo formulário operacional" do
    tenant = Tenant.create!(name: "Tenant sistema bloqueado #{SecureRandom.hex(3)}", slug: "tenant-sistema-bloqueado-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor)
    user = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner)

    sign_in owner

    patch admin_admin_user_path(user), params: {
      admin_user: {
        name: user.name,
        email: user.email,
        profile_id: agent_profile.id,
        acting_type: user.acting_type,
        active: "1",
        super_admin: "1"
      }
    }

    expect(response).to redirect_to(admin_admin_users_path)
    expect(user.reload).not_to be_system_admin
    expect(user.tenant).to eq(tenant)
    expect(user.profile).to eq(agent_profile)
  end

  it "ignora função horizontal incompatível com o perfil vertical enviado por payload" do
    tenant = Tenant.create!(name: "Tenant horizontal #{SecureRandom.hex(3)}", slug: "tenant-horizontal-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    manager_profile = create_vertical_profile(tenant, "Manager", 300, "corretores" => { "manage" => true })
    agent_profile = tenant.profiles.find_by!(key: "agent")
    support = Profile.create!(
      tenant: tenant,
      name: "Support",
      axis: "horizontal",
      vertical_profile: manager_profile,
      active: true,
      permissions: { "leads" => { "view" => true, "scope" => "team" } }
    )
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor)
    user = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner)

    sign_in owner

    patch admin_admin_user_path(user), params: {
      admin_user: {
        name: user.name,
        email: user.email,
        profile_id: agent_profile.id,
        horizontal_profile_id: support.id,
        acting_type: user.acting_type,
        active: "1"
      }
    }

    expect(response).to redirect_to(admin_admin_users_path)
    expect(user.reload.profile).to eq(agent_profile)
    expect(user.horizontal_profile).to be_nil
  end

  it "exibe função horizontal apenas como badge no organograma" do
    tenant = Tenant.create!(name: "Tenant organograma #{SecureRandom.hex(3)}", slug: "tenant-organograma-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    manager_profile = create_vertical_profile(tenant, "Manager", 300, "corretores" => { "manage" => true })
    support = Profile.create!(
      tenant: tenant,
      name: "Support",
      axis: "horizontal",
      vertical_profile: manager_profile,
      active: true,
      permissions: { "leads" => { "view" => true, "scope" => "team" } }
    )
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, name: "Owner Organograma")
    user = create(:admin_user, tenant: tenant, profile: manager_profile, horizontal_profile: support, manager: owner, name: "Gestor com função")

    sign_in owner

    get hierarchy_admin_admin_users_path

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    user_node = doc.at_css(%([data-user-id="#{user.id}"]))

    expect(user_node).to be_present
    expect(user_node.text).to include("Manager")
    expect(user_node.css(".hier-row__horizontal").text).to include("Função: Support")
    expect(doc.css("[data-user-id]").map { |node| node["data-user-id"].to_i }).to contain_exactly(owner.id, user.id)
  end
end

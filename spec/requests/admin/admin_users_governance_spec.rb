require "rails_helper"

RSpec.describe "Admin user governance", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
  end

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
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css(".ax-avatar.ax-avatar--md[role='img'][aria-label='Subordinado']")).to be_present
    expect(doc.at_css("a[aria-label='Editar usuário Subordinado']")).to be_present
    expect(doc.at_css("button[aria-label='Excluir usuário Subordinado']")).to be_present
    expect(doc.at_css(".ax-workspace-heading")).to be_present
    expect(doc.at_css('section.ax-filter-form[role="search"]')).to be_present
    expect(doc.css('.ax-filter-form label[for]').size).to eq(5)
    expect(doc.at_css('table.ax-table caption.tw-sr-only')).to be_present
    expect(doc.css('table.ax-table thead th[scope="col"]').size).to eq(8)
    expect(doc.css('table.ax-table thead th[scope="col"]').map(&:text)).to include("Leads")
    expect(doc.at_css('select#reassign_to_id[name="reassign_to_id"][data-reassign-delete-target="select"]')).to be_present
    expect(doc.at_css("#reassignDeleteModal .ax-form-actions--static")).to be_present
    expect(doc.at_css("#inactivateUserModal")).to be_present
    expect(doc.at_css('select#inactivate_reassign_to_id[name="reassign_to_id"][data-admin-user-inactivation-target="select"]')).to be_present

    get admin_admin_user_path(subordinate)
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css(".ax-avatar.ax-avatar--xl[role='img'][aria-label='Subordinado']")).to be_present

    get edit_admin_admin_user_path(subordinate)
    expect(response).to have_http_status(:ok)

    get edit_admin_admin_user_path(outside)
    expect(response).to redirect_to(admin_admin_users_path)
  end

  it "exibe a quantidade de leads atribuida a cada usuario da conta" do
    tenant = Tenant.create!(name: "Tenant leads usuarios #{SecureRandom.hex(3)}", slug: "tenant-leads-usuarios-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro tenant leads #{SecureRandom.hex(3)}", slug: "outro-tenant-leads-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, name: "Owner Leads")
    broker = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Corretor com Leads")
    without_leads = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Corretor sem Leads")
    other_user = create(:admin_user, tenant: other_tenant, name: "Outro tenant")

    create_list(:lead, 3, tenant: tenant, admin_user: broker)
    create(:lead, tenant: other_tenant, admin_user: other_user)

    sign_in owner

    get admin_admin_users_path

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)

    broker_row = doc.css("table.ax-table tbody tr").find { |row| row.text.include?(broker.name) }
    without_leads_row = doc.css("table.ax-table tbody tr").find { |row| row.text.include?(without_leads.name) }

    expect(broker_row.css("td")[5].text.squish).to eq("3")
    expect(without_leads_row.css("td")[5].text.squish).to eq("0")
    expect(response.body).not_to include(other_user.name)
  end

  it "lista apenas usuarios ativos por padrao e permite consultar inativos por filtro explicito" do
    tenant = Tenant.create!(name: "Tenant usuarios ativos #{SecureRandom.hex(3)}", slug: "tenant-usuarios-ativos-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, name: "Owner ativo")
    active_broker = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Corretor Ativo", active: true)
    inactive_broker = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Corretor Inativo", active: false)

    sign_in owner

    get admin_admin_users_path

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    row_text = doc.css("table.ax-table tbody tr").map(&:text).join("\n")
    expect(row_text).to include(active_broker.name)
    expect(row_text).not_to include(inactive_broker.name)
    expect(doc.at_css('select[name="status"] option[value="active"][selected]')).to be_present

    get admin_admin_users_path(status: "inactive")

    expect(response).to have_http_status(:ok)
    row_text = Nokogiri::HTML(response.body).css("table.ax-table tbody tr").map(&:text).join("\n")
    expect(row_text).not_to include(active_broker.name)
    expect(row_text).to include(inactive_broker.name)
  end

  it "inativa usuario transferindo leads, imoveis e vinculos de corretor para outro usuario ativo" do
    tenant = Tenant.create!(name: "Tenant inativacao #{SecureRandom.hex(3)}", slug: "tenant-inativacao-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, name: "Owner")
    broker = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Corretor Saindo")
    target = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Corretor Destino")
    lead = create(:lead, tenant: tenant, admin_user: broker)
    habitation = create(:habitation, tenant: tenant, admin_user: broker)
    assignment = HabitationBrokerAssignment.create!(habitation: habitation, admin_user: broker, role: "captador")

    sign_in owner

    patch inactivate_admin_admin_user_path(broker), params: {
      portfolio_action: "reassign",
      reassign_to_id: target.id
    }

    expect(response).to redirect_to(admin_admin_users_path(status: "inactive"))
    expect(broker.reload).not_to be_active
    expect(broker.display_on_site).to eq(false)
    expect(lead.reload.admin_user_id).to eq(target.id)
    expect(habitation.reload.admin_user_id).to eq(target.id)
    expect(assignment.reload.admin_user_id).to eq(target.id)
    follow_redirect!
    expect(response.body).to include("Carteira transferida para Corretor Destino")
  end

  it "inativa usuario desvinculando carteira quando escolhido no modal" do
    tenant = Tenant.create!(name: "Tenant desvincular #{SecureRandom.hex(3)}", slug: "tenant-desvincular-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, name: "Owner")
    broker = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Corretor Saindo")
    lead = create(:lead, tenant: tenant, admin_user: broker)
    habitation = create(:habitation, tenant: tenant, admin_user: broker)
    HabitationBrokerAssignment.create!(habitation: habitation, admin_user: broker, role: "captador")

    sign_in owner

    patch inactivate_admin_admin_user_path(broker), params: { portfolio_action: "detach" }

    expect(response).to redirect_to(admin_admin_users_path(status: "inactive"))
    expect(broker.reload).not_to be_active
    expect(lead.reload.admin_user_id).to be_nil
    expect(habitation.reload.admin_user_id).to be_nil
    expect(HabitationBrokerAssignment.where(admin_user_id: broker.id)).to be_empty
    follow_redirect!
    expect(response.body).to include("Carteira desvinculada")
  end

  it "bloqueia inativacao direta pelo formulario geral sem decisao de carteira" do
    tenant = Tenant.create!(name: "Tenant bloqueio inativacao #{SecureRandom.hex(3)}", slug: "tenant-bloqueio-inativacao-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    owner = create(:admin_user, tenant: tenant, profile: owner_profile, role: :editor, name: "Owner")
    broker = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Corretor Ativo")

    sign_in owner

    patch admin_admin_user_path(broker), params: {
      admin_user: {
        name: broker.name,
        email: broker.email,
        access_profile_id: agent_profile.id,
        acting_type: broker.acting_type,
        active: "0"
      }
    }

    expect(response).to redirect_to(admin_admin_users_path)
    expect(broker.reload).to be_active
    follow_redirect!
    expect(response.body).to include("Use a ação Inativar")
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
    expect(response.body).to include('class="au-form"', "au-form-grid")
    expect(response.body).not_to include("admin-users-form-styles")
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
    form = Nokogiri::HTML(response.body)
    expect(form.at_css('input[type="email"][name="admin_user[email]"]')).to be_present
    expect(form.css('input[type="tel"][data-controller="phone-input"]').size).to eq(2)
    expect(form.at_css('input[type="date"][name="admin_user[birth_date]"]')).to be_present
    expect(form.at_css('textarea[name="admin_user[biography]"]')).to be_present
    expect(form.css(".au-form label.au-field")).to be_empty
  end

  it "não exibe campos de senha ao editar uma identidade espelho" do
    tenant = Tenant.create!(name: "Tenant espelho #{SecureRandom.hex(3)}", slug: "tenant-espelho-#{SecureRandom.hex(3)}")
    source_tenant = Tenant.create!(name: "Origem espelho #{SecureRandom.hex(3)}", slug: "origem-espelho-#{SecureRandom.hex(3)}")
    owner = create(:admin_user, tenant: tenant, profile: tenant.profiles.find_by!(key: "tenant_owner"), role: :editor)
    primary = create(:admin_user, tenant: source_tenant, profile: source_tenant.profiles.find_by!(key: "agent"), email: "origem-#{SecureRandom.hex(3)}@example.com")
    mirror = create(:admin_user, tenant: tenant, profile: tenant.profiles.find_by!(key: "agent"), manager: owner, primary_admin_user: primary, contact_email: primary.email)

    sign_in owner
    get edit_admin_admin_user_path(mirror)

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.css('input[type="password"]')).to be_empty
    expect(doc.text).to include("e-mail e senha pertencem à conta de origem", primary.email)
    expect(doc.at_css(".ax-inline-notice--info")).to be_present
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

  it "permite salvar telefone secundário normalizado pelo formulário de usuário" do
    tenant = Tenant.create!(name: "Tenant telefone usuario #{SecureRandom.hex(3)}", slug: "tenant-telefone-usuario-#{SecureRandom.hex(3)}")
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
        secondary_phone: "47 9972-9441"
      }
    }

    expect(response).to redirect_to(admin_admin_users_path)
    expect(user.reload.secondary_phone).to eq("5547999729441")
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
    owner_node = doc.css(%([data-user-id="#{owner.id}"])).find { |node| node.at_css(".ax-avatar.ax-avatar--sm") }

    expect(user_node).to be_present
    expect(owner_node).to be_present
    avatar = owner_node.at_css(".ax-avatar.ax-avatar--sm")
    expect(avatar).to be_present
    expect([avatar["aria-label"], avatar["alt"]]).to include("Owner Organograma")
    expect(user_node.text).to include("Manager")
    expect(user_node.css(".hier-row__horizontal").text).to include("Função: Support")
    expect(doc.css("[data-user-id]").map { |node| node["data-user-id"].to_i }).to contain_exactly(owner.id, user.id)
  end
end

require "rails_helper"

RSpec.describe "Admin::DistributionRules", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "carrega o layout para System Admin sem tenant sem erro interno" do
    sign_out admin
    sign_in create(:admin_user, super_admin: true)

    get admin_distribution_rules_path

    expect(response).not_to have_http_status(:internal_server_error)
  end

  it "renderiza o formulario com objetivo em modal, aside e dados de equipe em cascata" do
    manager = create(:admin_user, :admin, name: "Gestor Praia")
    create(:admin_user, name: "Corretor Cascata", manager: manager)
    Profile.create!(
      tenant: admin.tenant,
      name: "Coordenador",
      axis: "vertical",
      position: 2_100,
      permissions: { "distribution_rules" => { "manage" => true } }
    )

    get new_admin_distribution_rule_path

    doc = Nokogiri::HTML(response.body)
    vertical_profile_ids = admin.tenant.profiles.ordered_vertical.pluck(:id).map(&:to_s)
    rendered_profile_ids = doc.css("#distribution_rule_hierarchy_filter select[data-profile-id]").map { |select| select["data-profile-id"] }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("distribution-rule-workspace")
    expect(response.body).to include("Configuração da regra")
    expect(response.body).to include("Distribuição vertical")
    expect(doc.css("#distribution_rule_hierarchy_filter select[data-controller='tom-select']").size).to eq(vertical_profile_ids.size)
    expect(response.body).to include("Gestor Praia")
    expect(response.body).to include("Corretor Cascata")
    expect(rendered_profile_ids).to eq(vertical_profile_ids)
    expect(response.body).to include("Entrega para um corretor por vez")
    expect(response.body).to include("sorteio ponderado")
    expect(response.body).to include("O primeiro que aceitar assume o lead")
    expect(response.body).to include("Filtro opcional pela faixa de valor do lead")
  end

  it "limita selecao de fila a subarvore do usuario logado com permissao de distribuicao" do
    tenant = admin.tenant
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gerente Distribuição",
      axis: "vertical",
      position: 2_100,
      permissions: { "distribution_rules" => { "manage" => true } }
    )
    agent_profile = tenant.profiles.find_or_create_by!(key: "agent") do |profile|
      profile.name = "Agent"
      profile.axis = "vertical"
      profile.permissions = Profile.default_permissions_for("Corretor")
    end
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: admin, name: "Gerente Logado")
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager, name: "Corretor Subordinado")
    outside = create(:admin_user, tenant: tenant, profile: agent_profile, manager: admin, name: "Corretor Fora da Subarvore")

    sign_in manager

    post admin_distribution_rules_path, params: {
      agent_select: [subordinate.id.to_s, outside.id.to_s],
      distribution_rule: {
        name: "Regra Subarvore",
        business_type: "ambos",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0"
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(DistributionRule.last))
    expect(DistributionRule.last.distribution_rule_agents.pluck(:admin_user_id)).to eq([subordinate.id])
  end

  it "renderiza a hierarquia travada do perfil logado para baixo em usuarios intermediarios" do
    tenant = admin.tenant
    director_profile = Profile.create!(
      tenant: tenant,
      name: "Diretoria",
      axis: "vertical",
      position: 2_100,
      permissions: { "distribution_rules" => { "manage" => true } }
    )
    coordinator_profile = Profile.create!(
      tenant: tenant,
      name: "Coordenacao",
      axis: "vertical",
      position: 2_200,
      permissions: { "distribution_rules" => { "manage" => true } }
    )
    agent_profile = tenant.profiles.find_or_create_by!(key: "agent") do |profile|
      profile.name = "Agent"
      profile.axis = "vertical"
      profile.permissions = Profile.default_permissions_for("Corretor")
    end
    director = create(:admin_user, tenant: tenant, profile: director_profile, manager: admin, name: "Diretora")
    coordinator = create(:admin_user, tenant: tenant, profile: coordinator_profile, manager: director, name: "Coordenador Logado")
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: coordinator, name: "Corretor da Coordenacao")
    create(:admin_user, tenant: tenant, profile: agent_profile, manager: director, name: "Corretor da Diretoria")

    sign_in coordinator

    get new_admin_distribution_rule_path

    doc = Nokogiri::HTML(response.body)
    rendered_profile_ids = doc.css("#distribution_rule_hierarchy_filter select[data-profile-id]").map { |select| select["data-profile-id"].to_i }

    expect(response).to have_http_status(:ok)
    expect(rendered_profile_ids).to eq([coordinator_profile.id, agent_profile.id])
    expect(doc.at_css("#distribution_rule_hierarchy_filter")["data-hierarchical-user-filter-locked-user-id-value"]).to eq(coordinator.id.to_s)
    expect(response.body).to include("Coordenador Logado")
    expect(response.body).to include("Corretor da Coordenacao")
    expect(response.body).not_to include("Diretora")
    expect(response.body).not_to include("Corretor da Diretoria")
  end

  it "mantem formularios da Meta em cascata pelas paginas selecionadas" do
    page_a = create(:meta_facebook_page, name: "Página A", page_id: "page-a")
    page_b = create(:meta_facebook_page, name: "Página B", page_id: "page-b")
    form_a = create(:meta_lead_form, meta_facebook_page: page_a, name: "Form Página A", form_id: "form-a")
    form_b = create(:meta_lead_form, meta_facebook_page: page_b, name: "Form Página B", form_id: "form-b")

    get new_admin_distribution_rule_path

    doc = Nokogiri::HTML(response.body)
    new_form_options = doc.css("select[name='distribution_rule[meta_forms][]'] option").map { |option| option["value"] }
    expect(new_form_options).to be_empty

    rule = create(
      :distribution_rule,
      source_meta: true,
      meta_page_ids: [page_a.page_id],
      meta_forms: [form_a.form_id]
    )

    get edit_admin_distribution_rule_path(rule)

    doc = Nokogiri::HTML(response.body)
    edit_form_options = doc.css("select[name='distribution_rule[meta_forms][]'] option").map { |option| option["value"] }
    expect(edit_form_options).to include(form_a.form_id)
    expect(edit_form_options).not_to include(form_b.form_id)
  end

  it "salva a fila de distribuicao a partir do select de corretores ao criar" do
    receiver = create(:admin_user, :admin, name: "Administrador")

    post admin_distribution_rules_path, params: {
      agent_select: [receiver.id.to_s],
      distribution_rule: {
        name: "Regra Meta",
        business_type: "ambos",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0"
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(DistributionRule.last))
    rule = DistributionRule.last
    expect(rule.distribution_rule_agents.pluck(:admin_user_id)).to eq([receiver.id])
  end

  it "bloqueia Pocket no formulario quando o link seguro do Push nao esta habilitado" do
    LeadSetting.instance.update!(secure_links_enabled: false, secure_link_push: true)

    get new_admin_distribution_rule_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Para usar Pocket, habilite o")
    expect(response.body).to include(edit_admin_lead_setting_path)
    doc = Nokogiri::HTML(response.body)
    pocket_input = doc.at_css("input#checkPocket")
    expect(pocket_input["disabled"]).to eq("disabled")
  end

  it "forca Pocket desligado ao salvar regra sem link seguro do Push" do
    LeadSetting.instance.update!(secure_links_enabled: false, secure_link_push: true)

    post admin_distribution_rules_path, params: {
      distribution_rule: {
        name: "Regra Sem Link Seguro",
        business_type: "ambos",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0",
        pocket_active: "1",
        pocket_time: "5"
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(DistributionRule.last))
    expect(DistributionRule.last.pocket_active).to be(false)
  end

  it "permite Pocket quando link seguro do Push esta habilitado" do
    LeadSetting.instance.update!(secure_links_enabled: true, secure_link_push: true)

    post admin_distribution_rules_path, params: {
      distribution_rule: {
        name: "Regra Com Link Seguro",
        business_type: "ambos",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0",
        pocket_active: "1",
        pocket_time: "5"
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(DistributionRule.last))
    expect(DistributionRule.last.pocket_active).to be(true)
  end

  it "atualiza a fila de distribuicao a partir do select de corretores ao editar" do
    first_receiver = create(:admin_user, :admin)
    second_receiver = create(:admin_user, :admin)
    rule = create(:distribution_rule)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_receiver)

    patch admin_distribution_rule_path(rule), params: {
      agent_select: [second_receiver.id.to_s],
      distribution_rule: {
        name: rule.name,
        business_type: "ambos",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0"
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(rule))
    expect(rule.reload.distribution_rule_agents.pluck(:admin_user_id)).to eq([second_receiver.id])
  end

  it "preserva a ordem enviada pela fila quando os nested attributes estao presentes" do
    first_receiver = create(:admin_user, :admin)
    second_receiver = create(:admin_user, :admin)
    rule = create(:distribution_rule)
    first_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_receiver, position: 1)
    second_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: second_receiver, position: 2)

    patch admin_distribution_rule_path(rule), params: {
      agent_select: [first_receiver.id.to_s, second_receiver.id.to_s],
      distribution_rule: {
        name: rule.name,
        business_type: "ambos",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0",
        distribution_rule_agents_attributes: {
          "0" => { id: first_agent.id, admin_user_id: first_receiver.id, position: 2, weight: 1 },
          "1" => { id: second_agent.id, admin_user_id: second_receiver.id, position: 1, weight: 1 }
        }
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(rule))
    expect(rule.reload.distribution_rule_agents.order(:position).pluck(:admin_user_id)).to eq([second_receiver.id, first_receiver.id])
  end

  it "salva os pesos dos corretores no modo performance" do
    first_receiver = create(:admin_user, :admin)
    second_receiver = create(:admin_user, :admin)

    post admin_distribution_rules_path, params: {
      agent_select: [first_receiver.id.to_s, second_receiver.id.to_s],
      distribution_rule: {
        name: "Regra Performance",
        business_type: "ambos",
        distribution_mode: "performance",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0",
        distribution_rule_agents_attributes: {
          "0" => { admin_user_id: first_receiver.id, position: 1, weight: 2 },
          "1" => { admin_user_id: second_receiver.id, position: 2, weight: 5 }
        }
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(DistributionRule.last))
    weights = DistributionRule.last.distribution_rule_agents.index_by(&:admin_user_id).transform_values(&:weight)
    expect(weights).to include(first_receiver.id => 2, second_receiver.id => 5)
  end

  it "salva faixa de preco enviada com mascara pt-BR" do
    post admin_distribution_rules_path, params: {
      distribution_rule: {
        name: "Regra Alto Padrao",
        business_type: "venda",
        distribution_mode: "rotary",
        active: "1",
        source_site: "1",
        source_meta: "0",
        source_portal: "0",
        source_webhook: "0",
        min_price: "1.500.000,00",
        max_price: "2.750.000,00"
      }
    }

    expect(response).to redirect_to(admin_distribution_rule_path(DistributionRule.last))
    rule = DistributionRule.last
    expect(rule.min_price).to eq(1_500_000)
    expect(rule.max_price).to eq(2_750_000)
  end

  it "permite reordenar a fila pela tela de detalhe" do
    first_receiver = create(:admin_user, :admin)
    second_receiver = create(:admin_user, :admin)
    rule = create(:distribution_rule)
    first_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_receiver, position: 1)
    second_agent = create(:distribution_rule_agent, distribution_rule: rule, admin_user: second_receiver, position: 2)

    patch reorder_agents_admin_distribution_rule_path(rule), params: {
      agent_ids: [second_agent.id, first_agent.id]
    }

    expect(response).to redirect_to(admin_distribution_rule_path(rule))
    expect(rule.reload.distribution_rule_agents.order(:position).pluck(:id)).to eq([second_agent.id, first_agent.id])
  end

  it "mostra as configuracoes principais da regra no detalhe" do
    meta_page = create(:meta_facebook_page, name: "Salute Imóveis", page_id: "page-1")
    meta_form = create(:meta_lead_form, meta_facebook_page: meta_page, name: "Captação Praia Brava", form_id: "form-1")
    rule = create(
      :distribution_rule,
      name: "Elite",
      source_meta: true,
      source_webhook: true,
      source_site: true,
      notify_email: true,
      meta_page_ids: [meta_page.page_id],
      meta_forms: [meta_form.form_id],
      webhook_tags: ["elite"]
    )

    get admin_distribution_rule_path(rule)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Configuração da regra")
    expect(response.body).to include("Salute Imóveis")
    expect(response.body).to include("Captação Praia Brava")
    expect(response.body).to include("Check-in geolocalizado")
    expect(response.body).to include("Notificações")
  end
end

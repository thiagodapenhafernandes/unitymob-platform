require "rails_helper"

RSpec.describe Profile, "governança vertical/horizontal", type: :model do
  let(:tenant) { Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}") }

  it "mantém Tenant Owner no topo da hierarquia vertical" do
    profile = tenant.profiles.find_by!(key: "tenant_owner")
    profile.update!(position: 500, locked: false)

    expect(profile).to be_vertical
    expect(profile).to be_locked
    expect(profile.position).to eq(0)
    expect(profile).to be_admin
  end

  it "mantém Agent como último perfil vertical fixo" do
    profile = tenant.profiles.find_by!(key: "agent")
    profile.update!(position: 10, locked: false)

    expect(profile).to be_vertical
    expect(profile).to be_locked
    expect(profile.position).to eq(10_000)
  end

  it "permite perfil vertical customizado entre Tenant Owner e Agent" do
    profile = described_class.create!(
      tenant: tenant,
      name: "Director",
      axis: "vertical",
      position: 150,
      permissions: { "leads" => { "view" => true, "scope" => "team" } }
    )

    expect(profile).to be_vertical
    expect(profile).not_to be_locked
    expect(profile.position).to eq(150)
  end

  it "bloqueia perfil vertical customizado fora do intervalo entre Tenant Owner e Agent" do
    before_owner = described_class.new(tenant: tenant, name: "Acima do owner", axis: "vertical", position: 0, permissions: {})
    after_agent = described_class.new(tenant: tenant, name: "Abaixo do agent", axis: "vertical", position: 10_000, permissions: {})

    expect(before_owner).not_to be_valid
    expect(before_owner.errors[:position]).to be_present
    expect(after_agent).not_to be_valid
    expect(after_agent.errors[:position]).to be_present
  end

  it "não permite dois perfis verticais na mesma posição dentro do Tenant" do
    described_class.create!(tenant: tenant, name: "Director", axis: "vertical", position: 150, permissions: {})
    duplicated = described_class.new(tenant: tenant, name: "Superintendent", axis: "vertical", position: 150, permissions: {})

    expect(duplicated).not_to be_valid
    expect(duplicated.errors[:position]).to be_present
  end

  it "usa chaves canônicas mesmo quando nomes legados são informados" do
    owner = tenant.profiles.find_by!(key: "tenant_owner")
    agent = tenant.profiles.find_by!(key: "agent")

    expect(owner.key).to eq("tenant_owner")
    expect(owner.position).to eq(0)
    expect(agent.key).to eq("agent")
    expect(agent.position).to eq(10_000)
  end

  it "exige que perfil horizontal esteja anexado a um perfil vertical do mesmo Tenant" do
    vertical = described_class.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})

    horizontal = described_class.create!(
      tenant: tenant,
      name: "Support",
      axis: "horizontal",
      vertical_profile: vertical,
      permissions: { "whatsapp_inbox" => { "view" => true, "scope" => "own" } }
    )

    expect(horizontal).to be_horizontal
    expect(horizontal.vertical_profile).to eq(vertical)
    expect(horizontal.position).to be_nil
  end

  it "não permite perfil horizontal sem perfil vertical" do
    profile = described_class.new(tenant: tenant, name: "Finance", axis: "horizontal", permissions: {})

    expect(profile).not_to be_valid
    expect(profile.errors[:vertical_profile]).to be_present
  end

  it "permite converter o eixo de um perfil não fixo quando a nova forma é válida" do
    profile = described_class.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})

    profile.axis = "horizontal"
    profile.vertical_profile = tenant.profiles.find_by!(key: "tenant_owner")

    expect(profile).to be_valid
  end

  it "permite mover uma função horizontal para outro perfil vertical" do
    manager = described_class.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    director = described_class.create!(tenant: tenant, name: "Director", axis: "vertical", position: 150, permissions: {})
    horizontal = described_class.create!(tenant: tenant, name: "Support", axis: "horizontal", vertical_profile: manager, permissions: {})

    horizontal.vertical_profile = director

    expect(horizontal).to be_valid
  end

  it "declara seções macro e vínculo de recursos filhos no catálogo" do
    expect(described_class.section_resource?(:conta)).to be(true)
    expect(described_class.section_resource?(:access_security)).to be(false)
    expect(described_class.parent_section_for(:access_security)).to eq("conta")
    expect(described_class.parent_section_for(:agenda_fotografia)).to eq("integracoes")
    expect(described_class.parent_section_for(:commercial_contracts)).to eq("comercial")
    expect(described_class.resource_for(:conta)[:included_items]).to include("Perfis")
    expect(described_class.resource_for(:commercial_contracts)[:actions]).to eq(%w[manage])
    expect(described_class.sidebar_permissions_for(:operation)).to include([:view, :comercial], [:manage, :automacoes], [:manage, :distribution_rules])
    expect(described_class.sidebar_permissions_for(:operation)).not_to include([:view, :distribution_rules])
    expect(described_class.sidebar_permissions_for(:management)).to include([:manage, :corretores])
    expect(described_class.sidebar_permissions_for(:account)).to eq([[:manage, :conta]])
    expect(described_class.sidebar_items_for(:product).map { |item| item[:label] || item[:dynamic] || item[:group] }).to include("dashboard_home", "Imóveis", "Leads", "Bolsão", "lead_pipelines")
    expect(described_class.sidebar_menu_count_for(:product)).to eq(6)
    expect(described_class.sidebar_items_for(:operation).map { |item| item[:label] || item[:group] }).to include("Comercial", "WhatsApp", "Captações")
    commercial_group = described_class.sidebar_items_for(:operation).find { |item| item[:group] == "Comercial" }
    expect(commercial_group[:children].find { |item| item[:label] == "Contratos B2B" }[:permission]).to eq([:manage, :commercial_contracts])
    expect(described_class.sidebar_items_for(:management).map { |item| item[:label] }).to include("Proprietários", "Usuários", "Metas de Captação")
    expect(described_class.sidebar_items_for(:growth).map { |item| item[:label] }).to include("Oportunidades", "Campanhas", "Alertas")
    expect(described_class.sidebar_items_for(:public_site).map { |item| item[:label] }).to include("Dashboard SEO", "Rodapé")
    expect(described_class.sidebar_items_for(:account).find { |item| item[:label] == "Segurança de Acesso" }[:permission]).to eq([:manage, :access_security])
  end

  it "organiza a tela de permissões pela mesma árvore do menu lateral" do
    sections = described_class.permission_tree_sections
    product = sections.find { |section| section[:key] == :product }
    account = sections.find { |section| section[:key] == :account }
    integrations = sections.find { |section| section[:key] == :integrations }
    dashboard = described_class.resource_for(:dashboard)
    dashboard_leads = described_class.resource_for(:dashboard_leads)

    expect(sections.map { |section| section[:key] }).to include(:product, :operation, :public_site, :integrations, :settings, :account)
    expect(product[:resources].map { |resource| resource[:key] }).to include("dashboard", "imoveis", "leads", "lead_pool", "lead_funnels")
    expect(product[:resources].map { |resource| resource[:key] }.first(5)).to eq(%w[dashboard imoveis leads lead_pool lead_funnels])
    expect(described_class.permission_children_for(:leads).map { |resource| resource[:key] }).to include("lead_reports")
    expect(described_class.permission_children_for(:lead_funnels).map { |resource| resource[:key] }).to eq(%w[lead_funnel_rental lead_funnel_sale])
    expect(dashboard[:sidebar_items].map { |item| item[:dynamic] }).to include("dashboard_home")
    expect(dashboard_leads[:permission_items].map { |item| item[:label] }).to include("Aba Leads")
    expect(described_class.permission_children_for(:dashboard).map { |resource| resource[:key] }).to include("dashboard_leads")
    expect(described_class.permission_children_for(:dashboard)).not_to include(
      described_class.resource_for(:dashboard_broker_performance),
      described_class.resource_for(:dashboard_campaign_performance)
    )
    expect(described_class.permission_children_for(:dashboard_leads).map { |resource| resource[:key] }).to include("dashboard_broker_performance", "dashboard_campaign_performance")
    expect(account[:resource][:key]).to eq("conta")
    expect(account[:resources].map { |resource| resource[:key] }).to include("access_security", "access_audit", "data_export_audit")
    expect(integrations[:resource][:key]).to eq("integracoes")
    expect(integrations[:resources].map { |resource| resource[:key] }).to include("agenda_fotografia", "inbound_webhooks")
    synced_properties = described_class.sidebar_items_for(:integrations).find { |item| item[:label] == "Imóveis sincronizados" }
    expect(synced_properties[:permission_all]).to eq([[:manage, :integracoes], [:view, :imoveis]])
  end

  it "permite reordenar menus por perfil sem aceitar chaves fora do catálogo" do
    profile = described_class.create!(
      tenant: tenant,
      name: "Menu customizado",
      axis: "vertical",
      position: 650,
      permissions: {
        described_class::MENU_ORDER_PERMISSION_KEY => {
          "product" => %w[leads dashboard inexistente imoveis]
        }
      }
    )

    expect(described_class.normalize_menu_order("product" => %w[lead_pool leads fake])).to eq("product" => %w[lead_pool leads])
    expect(described_class.sidebar_items_for(:product, profile: profile).map { |item| item[:label] || item[:dynamic] || item[:group] }.first(3)).to eq(["Leads", "dashboard_home", "Imóveis"])
    product = described_class.permission_tree_sections(profile: profile).find { |section| section[:key] == :product }
    expect(product[:resources].map { |resource| resource[:key] }.first(3)).to eq(%w[leads dashboard imoveis])
  end

  it "mantém apenas Tenant Owner e Agent como perfis fixos de eixo vertical" do
    owner = tenant.profiles.find_by!(key: "tenant_owner")
    agent = tenant.profiles.find_by!(key: "agent")

    owner.axis = "horizontal"
    owner.vertical_profile = described_class.create!(tenant: tenant, name: "Manager owner test", axis: "vertical", position: 200, permissions: {})
    agent.axis = "horizontal"
    agent.vertical_profile = owner.vertical_profile

    expect(owner).not_to be_valid
    expect(agent).not_to be_valid
    expect(owner.errors[:axis]).to be_present
    expect(agent.errors[:axis]).to be_present
  end

  it "bloqueia no banco perfis com eixo ou forma incompatível" do
    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          name: "Eixo inválido",
          axis: "diagonal",
          position: 500,
          permissions: {},
          active: true,
          locked: false,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          name: "Horizontal com posição",
          axis: "horizontal",
          vertical_profile_id: tenant.profiles.find_by!(key: "agent").id,
          position: 500,
          permissions: {},
          active: true,
          locked: false,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco função horizontal anexada a outro perfil horizontal" do
    vertical = described_class.create!(tenant: tenant, name: "Manager", axis: "vertical", position: 200, permissions: {})
    horizontal = described_class.create!(tenant: tenant, name: "Support", axis: "horizontal", vertical_profile: vertical, permissions: {})

    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          name: "Auditor inválido",
          axis: "horizontal",
          vertical_profile_id: horizontal.id,
          position: nil,
          permissions: {},
          active: true,
          locked: false,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco posições verticais fora da governança do Tenant" do
    common = {
      tenant_id: tenant.id,
      axis: "vertical",
      vertical_profile_id: nil,
      permissions: {},
      active: true,
      created_at: Time.current,
      updated_at: Time.current
    }

    expect {
      described_class.insert_all!([
        common.merge(
          name: "Owner fora do topo",
          key: "tenant_owner",
          position: 500,
          locked: true
        )
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect {
      described_class.insert_all!([
        common.merge(
          name: "Custom abaixo do Agent",
          key: nil,
          position: 10_000,
          locked: false
        )
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)

    expect {
      described_class.insert_all!([
        common.merge(
          name: "Custom travado",
          key: nil,
          position: 500,
          locked: true
        )
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "bloqueia no banco Agent deslocado para qualquer posição diferente de 10000" do
    expect {
      described_class.insert_all!([
        {
          tenant_id: tenant.id,
          name: "Agent abaixo do último nível",
          key: "agent",
          axis: "vertical",
          vertical_profile_id: nil,
          position: 10_001,
          permissions: {},
          active: true,
          locked: true,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "restringe o escopo horizontal ao limite vertical" do
    expect(described_class.restricted_scope("team", "all")).to eq("team")
    expect(described_class.restricted_scope("team", "own")).to eq("own")
    expect(described_class.restricted_scope("all", "team")).to eq("team")
    expect(described_class.restricted_scope("team", nil)).to eq("team")
  end

  it "ignora team configurado diretamente em perfil horizontal" do
    vertical = described_class.create!(
      tenant: tenant,
      name: "Coordenação vertical",
      axis: "vertical",
      position: 777,
      permissions: { "imoveis" => { "scope" => "all" } }
    )
    horizontal = described_class.create!(
      tenant: tenant,
      name: "Função operacional",
      axis: "horizontal",
      vertical_profile: vertical,
      permissions: { "imoveis" => { "scope" => "team" } }
    )

    expect(horizontal.configured_scope_for(:imoveis)).to be_nil
  end

  it "permite configurar escopo hierárquico nos recursos de auditoria" do
    resources = described_class::RESOURCES.index_by { |resource| resource.fetch(:key) }

    expect(resources.fetch("field_audit")).to include(scopeable: true)
    expect(resources.fetch("access_audit")).to include(scopeable: true)
    expect(resources.fetch("data_export_audit")).to include(scopeable: true)
    expect(resources.fetch("access_security")).to include(scopeable: true)
  end

  it "expoe relatorios de leads como permissao configuravel" do
    resource = described_class::RESOURCES.index_by { |item| item.fetch(:key) }.fetch("lead_reports")

    expect(resource).to include(
      label: "Relatórios de leads",
      actions: %w[view],
      scopeable: false
    )
    expect(described_class.default_permissions_for("Gerente").dig("lead_reports", "view")).to eq(true)
    expect(described_class.default_permissions_for("Administrativo").dig("lead_reports", "view")).to eq(true)
    expect(described_class.default_permissions_for("Corretor")).not_to have_key("lead_reports")
  end
end

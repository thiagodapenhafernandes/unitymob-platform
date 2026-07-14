require "rails_helper"

RSpec.describe "Admin::Field::AuditLogs", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "filtra auditoria de campo por perfil, corretor, executor, loja e IP" do
    admin = create(:admin_user, :admin)
    broker_profile = Tenant.default.profiles.find_by!(key: "agent")
    broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    other_profile = Profile.create!(
      tenant: Tenant.default,
      name: "Campo outro #{SecureRandom.hex(4)}",
      position: 700,
      permissions: Profile.default_permissions_for("Gerente")
    )
    broker = create(:admin_user, profile: broker_profile, name: "Corretor Campo Certo")
    actor = create(:admin_user, name: "Executor Campo")
    other = create(:admin_user, profile: other_profile, name: "Corretor Campo Errado")
    store = create(:store, name: "Loja Campo")
    other_store = create(:store, name: "Outra Loja")
    check_in = create(:check_in, admin_user: broker, store: store)
    other_check_in = create(:check_in, admin_user: other, store: other_store)

    create(:checkin_audit_log, action: "forced_closed", admin_user: broker, actor_admin_user: actor, check_in: check_in, ip: "10.30.0.1")
    create(:checkin_audit_log, action: "created", admin_user: other, check_in: other_check_in, ip: "10.40.0.1")

    sign_in admin

    get admin_field_audit_logs_path, params: {
      action_filter: "forced_closed",
      admin_user_id: broker.id,
      profile_id: broker_profile.id,
      actor_admin_user_id: actor.id,
      store_id: store.id,
      ip: "10.30.0.1"
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Corretor Campo Certo")
    expect(response.body).to include("Executor Campo")
    expect(response.body).to include("Loja Campo")
    expect(response.body).not_to include("10.40.0.1")
    expect(response.body).to include("Limpar")
  end

  it "limita auditoria de campo e contadores à subárvore do perfil vertical intermediário" do
    owner = create(:admin_user, :admin)
    tenant = owner.tenant
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gestor Campo #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 700,
      permissions: {
        "dashboard" => { "view" => true },
        "field_audit" => { "view" => true, "scope" => "team" }
      }
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner, name: "Gestor Campo")
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager, name: "Subordinado Campo")
    peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Par Campo")
    store = create(:store, name: "Loja Visível")

    subordinate_check_in = create(:check_in, admin_user: subordinate, store: store)
    peer_check_in = create(:check_in, admin_user: peer, store: store)
    create(:checkin_audit_log, action: "forced_closed", admin_user: subordinate, actor_admin_user: manager, check_in: subordinate_check_in, ip: "10.50.0.1")
    create(:checkin_audit_log, action: "flagged_suspicious", admin_user: peer, actor_admin_user: owner, check_in: peer_check_in, ip: "10.60.0.1")

    sign_in manager

    get admin_field_audit_logs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Subordinado Campo")
    expect(response.body).to include("10.50.0.1")
    expect(response.body).not_to include("Par Campo")
    expect(response.body).not_to include("10.60.0.1")
    stats = Nokogiri::HTML(response.body).css(".ax-metric-card").to_h do |card|
      [card.css(".ax-metric-card__label").text.squish, card.css(".ax-metric-card__value").text.squish]
    end
    expect(stats.fetch("Suspeitos")).to eq("0")
    expect(stats.fetch("Forçados")).to eq("1")
  end

  it "bloqueia acesso direto ao detalhe de auditoria de campo fora da subárvore" do
    owner = create(:admin_user, :admin)
    tenant = owner.tenant
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gestor Campo Detalhe #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 710,
      permissions: {
        "dashboard" => { "view" => true },
        "field_audit" => { "view" => true, "scope" => "team" }
      }
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner)
    peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner)
    peer_check_in = create(:check_in, admin_user: peer)
    peer_log = create(:checkin_audit_log, action: "created", admin_user: peer, check_in: peer_check_in)

    sign_in manager

    get admin_field_audit_log_path(peer_log)

    expect(response).to redirect_to(admin_field_audit_logs_path)
    expect(flash[:alert]).to match(/permissão/i)
  end
end

require "rails_helper"

RSpec.describe "Admin::Field::AuditLogs", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "filtra auditoria de campo por perfil, corretor, executor, loja e IP" do
    admin = create(:admin_user, :admin)
    broker_profile = Profile.create!(name: "Campo filtro #{SecureRandom.hex(4)}", permissions: Profile.default_permissions_for("Corretor"))
    other_profile = Profile.create!(name: "Campo outro #{SecureRandom.hex(4)}", permissions: Profile.default_permissions_for("Gerente"))
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
end

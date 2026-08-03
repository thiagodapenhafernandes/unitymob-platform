require "rails_helper"

RSpec.describe "Admin::UserActivitySessions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "activity-admin-#{SecureRandom.hex(8)}@salute.test") }

  before do
    host! "localhost"
  end

  it "exibe a auditoria operacional condensada para admin da conta" do
    activity_session = create_activity_session(admin)
    habitation = create(:habitation, tenant: admin.tenant, admin_user: admin, codigo: "AUD-123", titulo_anuncio: "Apartamento Auditado")
    activity_session.events.create!(
      tenant: admin.tenant,
      admin_user: admin,
      habitation: habitation,
      name: "catalog_search",
      occurred_at: 3.minutes.ago,
      query_text: "frente mar",
      result_count: 50,
      visible_habitation_ids: [habitation.id],
      filter_params: { "cidade" => "Balneário Camboriú", "telefone" => "[redigido]" }
    )
    activity_session.update!(events_count: 1)

    sign_in admin

    get admin_user_activity_sessions_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Auditoria operacional")
    expect(response.body).to include(admin.name)
    expect(response.body).to include("Celular")
    expect(response.body).to include("1 pesquisa")
    expect(response.body).to include("1 imóvel exibido")
    expect(response.body).to include("50")

    get admin_user_activity_session_path(activity_session)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sessão operacional")
    expect(response.body).to include("Imóveis exibidos")
    expect(response.body).to include("frente mar")
    expect(response.body).to include("REF: AUD-123")
    expect(response.body).to include("Balneário Camboriú")
    expect(response.body).to include("[redigido]")
  end

  it "bloqueia usuários que não são admin da conta mesmo com permissão de auditoria" do
    profile = Profile.create!(
      tenant: admin.tenant,
      name: "Auditor operacional #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 500,
      permissions: { "access_audit" => { "view" => true, "scope" => "all" } }
    )
    auditor = create(:admin_user, tenant: admin.tenant, profile: profile, role: :editor)

    sign_in auditor

    get admin_user_activity_sessions_path

    expect(response).to redirect_to(admin_root_path)
    follow_redirect!
    expect(response.body).to include("Acesso negado. Apenas administradores.")
  end

  it "mantém as sessões isoladas por conta" do
    current_session = create_activity_session(admin)
    other_tenant = Tenant.create!(name: "Outro tenant #{SecureRandom.hex(4)}", slug: "outro-activity-#{SecureRandom.hex(4)}")
    other_profile = other_tenant.profiles.find_by!(key: "tenant_owner")
    other_admin = create(:admin_user, :admin, tenant: other_tenant, profile: other_profile, name: "Admin Outra Conta")
    create_activity_session(other_admin)

    sign_in admin

    get admin_user_activity_sessions_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(current_session.admin_user.name)
    expect(response.body).not_to include("Admin Outra Conta")
  end

  private

  def create_activity_session(user)
    OperationalUserSession.create!(
      tenant: user.tenant,
      admin_user: user,
      token: SecureRandom.uuid,
      started_at: 35.minutes.ago,
      last_seen_at: 2.minutes.ago,
      duration_seconds: 1_980,
      events_count: 0,
      device_type: "Celular",
      browser: "Safari",
      platform: "iOS",
      entry_path: "/admin/habitations"
    )
  end
end

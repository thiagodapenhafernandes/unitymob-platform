require "rails_helper"

RSpec.describe "Admin system health", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "permite acesso ao Admin do Sistema" do
    admin = create(:admin_user, :admin, super_admin: true)
    sign_in admin, scope: :admin_user
    allow(::System::HealthSnapshot).to receive(:call).and_return(
      status: "healthy", http_status: 200, memory_available_percent: 40,
      disk_percent: 30, swap_used_mb: 0, http_ms: 100,
      puma: "active", solid_queue: "active", nginx: "active", database: "ok", cache: "ok"
    )

    get admin_system_health_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Saúde do sistema")
    expect(response.body).to include("Operacional")
    expect(response.body).to include("Saúde por tenant")
    expect(response.body).to include("Erros funcionais abertos")
    expect(response.body).to include("Ruído de tráfego")
  end

  it "bloqueia usuário de conta" do
    admin = create(:admin_user, :admin, super_admin: false)
    sign_in admin, scope: :admin_user

    get admin_system_health_path

    expect(response).to redirect_to(admin_root_path)
  end

  it "permite ao Admin do Sistema atualizar limites válidos" do
    admin = create(:admin_user, :admin, super_admin: true)
    sign_in admin, scope: :admin_user

    patch admin_system_health_path, params: {
      system_health_setting: {
        memory_available_warning_percent: 18, memory_available_critical_percent: 9,
        disk_warning_percent: 82, disk_critical_percent: 92,
        swap_warning_mb: 600, http_warning_ms: 1_800, http_critical_ms: 4_500,
        application_errors_warning: 6, application_errors_critical: 25,
        integration_failures_critical: 4
      }
    }

    expect(response).to redirect_to(admin_system_health_path(anchor: "thresholds"))
    expect(SystemHealthSetting.instance.http_critical_ms).to eq(4_500)
  end

  it "impede usuário de conta de alterar limites globais" do
    admin = create(:admin_user, :admin, super_admin: false)
    sign_in admin, scope: :admin_user

    expect do
      patch admin_system_health_path, params: { system_health_setting: { disk_warning_percent: 10 } }
    end.not_to change { SystemHealthSetting.instance.updated_at }

    expect(response).to redirect_to(admin_root_path)
  end

  it "mostra apenas o histórico do tenant selecionado" do
    admin = create(:admin_user, :admin, super_admin: true)
    tenant = Tenant.create!(name: "Conta histórica A", slug: "conta-historica-a-#{SecureRandom.hex(3)}", active: true)
    other_tenant = Tenant.create!(name: "Conta histórica B", slug: "conta-historica-b-#{SecureRandom.hex(3)}", active: true)
    SystemHealthSnapshot.create!(tenant: tenant, status: "warning", collected_at: Time.current, metrics: { open_errors: 7 })
    SystemHealthSnapshot.create!(tenant: other_tenant, status: "critical", collected_at: Time.current, metrics: { open_errors: 99 })
    sign_in admin, scope: :admin_user
    allow(::System::HealthSnapshot).to receive(:call).and_return(
      status: "healthy", http_status: 200, memory_available_percent: 40,
      disk_percent: 30, swap_used_mb: 0, http_ms: 100,
      puma: "active", solid_queue: "active", nginx: "active", database: "ok", cache: "ok"
    )

    get admin_system_health_path, params: { tenant_id: tenant.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(tenant.name, ">7<")
    expect(response.body).not_to include(">99<")
  end
end

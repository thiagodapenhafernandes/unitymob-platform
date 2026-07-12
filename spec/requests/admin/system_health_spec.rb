require "rails_helper"

RSpec.describe "Admin system health", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "permite acesso ao Admin do Sistema" do
    admin = create(:admin_user, :admin, super_admin: true)
    sign_in admin, scope: :admin_user
    allow(::System::HealthSnapshot).to receive(:call).and_return(status: "healthy", http_status: 200)

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
end

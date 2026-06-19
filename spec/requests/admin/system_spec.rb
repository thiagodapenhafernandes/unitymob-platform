require "rails_helper"

RSpec.describe "Admin::System", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  let(:profile_admin) { Profile.create!(name: "Administrador", permissions: { "admin" => true }) }

  it "redireciona usuário não autenticado" do
    get admin_system_path
    expect(response).to have_http_status(:redirect)
  end

  it "bloqueia admin da conta que NÃO é admin do sistema" do
    account_admin = create(:admin_user, profile: profile_admin, super_admin: false)
    sign_in account_admin, scope: :admin_user

    get admin_system_path
    expect(response).to redirect_to(admin_root_path)
    expect(flash[:alert]).to match(/Admin do Sistema/i)
  end

  it "permite acesso ao admin do sistema" do
    sys = create(:admin_user, super_admin: true)
    sign_in sys, scope: :admin_user

    get admin_system_path
    expect(response).to have_http_status(:ok)
  end
end

require "rails_helper"

RSpec.describe "Admin::AccountSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "account-settings-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o hub permitido no cabecalho compartilhado" do
    get admin_account_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Configurações da Conta", "Conta · Governança")
  end
end

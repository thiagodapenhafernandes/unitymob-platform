require "rails_helper"

RSpec.describe Admin::OmniauthCallbacksController, type: :controller do
  include Devise::Test::ControllerHelpers

  it "reconecta apenas a conta autenticada e preserva suas páginas selecionadas" do
    admin = create(:admin_user, :admin)
    integration = create(:user_meta_integration, admin_user: admin, selected_page_ids: ["salute"])
    other = create(:user_meta_integration, selected_page_ids: ["conexao"])
    request.env["devise.mapping"] = Devise.mappings[:admin_user]
    sign_in admin
    request.env["omniauth.auth"] = OmniAuth::AuthHash.new(uid: "shared-login", credentials: {token: "renewed"}, info: {name: "Admin", email: "admin@example.test"})
    allow(Facebook::MetaService).to receive(:exchange_access_token).with("renewed").and_return(nil)

    get :facebook

    expect(response).to redirect_to(admin_meta_integrations_path)
    expect(integration.reload.access_token).to eq("renewed")
    expect(integration.selected_page_ids).to eq(["salute"])
    expect(other.reload.selected_page_ids).to eq(["conexao"])
    expect(other.access_token).not_to eq("renewed")
  end
end

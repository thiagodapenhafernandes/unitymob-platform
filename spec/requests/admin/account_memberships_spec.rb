require "rails_helper"

RSpec.describe "Admin::AccountMemberships", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    host! "localhost"
    sign_in create(:admin_user, :admin)
  end

  it "renderiza o workspace tenant-scoped com formulário compartilhado" do
    get admin_account_memberships_path

    expect(response).to have_http_status(:ok)
    workspace = Nokogiri::HTML(response.body).at_css(".layout-settings-workspace")
    expect(workspace.to_html).to include("ax-workspace-heading", "ax-field-grid", "Nenhum acesso externo")
    expect(workspace.to_html).not_to match(/\bstyle\s*=|\bonclick\s*=/i)
    expect(workspace.at_css("label[for='account_membership_access_profile_id']")).to be_present
    expect(workspace.at_css("select#account_membership_access_profile_id[required]")).to be_present
  end
end

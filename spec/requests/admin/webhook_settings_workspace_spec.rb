require "rails_helper"

RSpec.describe "Admin::WebhookSettings workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o novo webhook no mesmo shell estrutural do índice" do
    get new_admin_webhook_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("webhook-settings-workspace")
    expect(response.body).to include("ax-workspace-main")
    expect(response.body).to include("ax-workspace-aside")
    expect(response.body).to include("webhook-settings-middle-contextbar")
    expect(response.body).to include("Detalhes da integração")
    expect(response.body).to include("Referência do webhook")
    expect(response.body).not_to include("container-fluid")
  end

  it "mantém a edição no workspace e isola a exclusão no aside" do
    webhook = WebhookSetting.create!(webhook_url: "https://example.com/hook", description: "CRM externo", enabled: true)

    get edit_admin_webhook_setting_path(webhook)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("webhook-settings-workspace")
    expect(response.body).to include("ax-workspace-aside")
    expect(response.body).to include("Governança")
    expect(response.body).to include("Excluir webhook")
    expect(response.body).not_to include("container-fluid")
  end
end

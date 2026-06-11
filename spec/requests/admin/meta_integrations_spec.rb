require "rails_helper"

RSpec.describe "Admin::MetaIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:integration) { create(:user_meta_integration, admin_user: admin) }
  let(:page) { create(:meta_facebook_page, user_meta_integration: integration) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "pagina a listagem de formularios da pagina" do
    30.times do |index|
      create(:meta_lead_form, meta_facebook_page: page, name: "Form #{index}", facebook_created_at: index.minutes.ago)
    end

    get list_forms_admin_meta_integrations_path(page_id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body.scan("bi-file-earmark-text").size).to eq(25)
    expect(response.body).to include("page_forms_#{page.id}_page_2")
    expect(response.body).to include("Carregando mais formulários")
  end

  it "renderiza a proxima pagina no frame correto" do
    30.times do |index|
      create(:meta_lead_form, meta_facebook_page: page, name: "Form #{index}", facebook_created_at: index.minutes.ago)
    end

    get list_forms_admin_meta_integrations_path(page_id: page.id, page: 2, frame_id: "page_forms_#{page.id}_page_2")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(turbo-frame id="page_forms_#{page.id}_page_2"))
    expect(response.body.scan("bi-file-earmark-text").size).to eq(5)
  end
end

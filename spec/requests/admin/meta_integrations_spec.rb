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

  it "renderiza a conta conectada com páginas no workspace compartilhado" do
    page

    get admin_meta_integrations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-operational-panel", "meta-integration-avatar--page")
    expect(response.body).to include("ax-record-item", "meta-integration-account", "ax-disclosure-card")
    expect(response.body).to include("Sincronizar Páginas", "Desconectar conta", page.name)
    expect(response.body).to include("Webhook Ativo") if page.active?
    expect(Nokogiri::HTML(response.body).at_css(".meta-integration-workspace").to_html).not_to match(/\bstyle\s*=/i)
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
    expect(response.body).not_to include("spinner-border", "list-unstyled", "border-bottom-dashed")
  end

  it "renderiza a proxima pagina no frame correto" do
    30.times do |index|
      create(:meta_lead_form, meta_facebook_page: page, name: "Form #{index}", facebook_created_at: index.minutes.ago)
    end

    get list_forms_admin_meta_integrations_path(page_id: page.id, page: 2)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(turbo-frame id="page_forms_#{page.id}_page_2"))
    expect(response.body.scan("bi-file-earmark-text").size).to eq(5)
  end

  it "limita a pagina solicitada e gera o frame no servidor" do
    30.times do |index|
      create(:meta_lead_form, meta_facebook_page: page, name: "Form #{index}", facebook_created_at: index.minutes.ago)
    end

    get list_forms_admin_meta_integrations_path(page_id: page.id, page: 999, frame_id: "frame_injetado")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(turbo-frame id="page_forms_#{page.id}_page_2"))
    expect(response.body).not_to include("frame_injetado")
    expect(response.body.scan("bi-file-earmark-text").size).to eq(5)
  end

  it "nao acessa paginas vinculadas a integracao de outro usuario" do
    integration
    another_admin = create(:admin_user, :admin)
    another_integration = create(:user_meta_integration, admin_user: another_admin)
    another_page = create(:meta_facebook_page, user_meta_integration: another_integration)

    get list_forms_admin_meta_integrations_path(page_id: another_page.id)

    expect(response).to have_http_status(:not_found)
  end

  it "nao expoe detalhes internos quando o job de sincronizacao falha ao enfileirar" do
    integration
    allow(MetaSyncJob).to receive(:perform_later).and_raise(StandardError, "token-secreto")

    post sync_pages_admin_meta_integrations_path, as: :json

    expect(response).to have_http_status(:internal_server_error)
    expect(response.parsed_body.fetch("message")).to eq("Não foi possível iniciar a sincronização. Tente novamente em instantes.")
    expect(response.body).not_to include("token-secreto")
  end

  it "anuncia o progresso da sincronizacao sem spinner legado" do
    integration.update!(sync_status: "processing", sync_progress: 37)

    get admin_meta_integrations_path

    document = Nokogiri::HTML(response.body)
    expect(document.at_css('[role="status"] .ax-spinner')).to be_present
    expect(document.at_css('progress[aria-label="Sincronização Meta: 37%"]')).to be_present
    expect(response.body).not_to include("fa-spin")
  end
end

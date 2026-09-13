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

  it "apresenta os recursos da conexão e preserva o login por POST" do
    get admin_meta_integrations_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Instagram Direct", "Formulários de anúncios", "Campanhas e anúncios", "O WhatsApp exige conexão própria")
    document = Nokogiri::HTML(response.body)
    form = document.at_css(".ax-integration-onboarding form")
    expect(form["method"]).to eq("post")
    expect(form["action"]).to eq(admin_user_facebook_omniauth_authorize_path)
  end

  it "consulta somente a integração do usuário e renderiza instruções sem expor token" do
    integration
    expect(Facebook::PermissionCheck).to receive(:call).with(integration).and_return({error: "Consulta indisponível"})
    get permissions_admin_meta_integrations_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("meta_permissions", "Como liberar o acesso", "Atualizar autorização", "rerequest")
    expect(response.body).not_to include(integration.access_token)
  end

  it "não usa integração de outro usuário" do
    create(:user_meta_integration, admin_user: create(:admin_user, :admin))
    expect(Facebook::PermissionCheck).not_to receive(:call)
    get permissions_admin_meta_integrations_path
    expect(response).to have_http_status(:not_found)
  end

  it "valida a conta de anúncios antes de vinculá-la" do
    service = instance_double(Facebook::MetaService)
    allow(Facebook::MetaService).to receive(:new).with(integration.access_token).and_return(service)
    allow(service).to receive(:ad_account).with("123456").and_return({"account_id" => "123456", "name" => "Conta correta"})
    patch ad_account_admin_meta_integrations_path, params: {meta_integration: {ad_account_id: "act_123456"}}
    expect(response).to redirect_to(admin_meta_integrations_path)
    expect(integration.reload.ad_account_id).to eq("123456")
    expect(integration.ad_account_name).to eq("Conta correta")
  end

  it "recusa ID inválido sem substituir a configuração" do
    integration.update!(ad_account_id: "123456")
    expect(Facebook::MetaService).not_to receive(:new)
    patch ad_account_admin_meta_integrations_path, params: {meta_integration: {ad_account_id: "../me"}}
    expect(integration.reload.ad_account_id).to eq("123456")
    expect(flash[:alert]).to include("Gerenciador de Anúncios", "administrador do negócio", "atualize a autorização")
  end

  it "carrega contas em frame sem bloquear a página principal nem escolher pela empresa" do
    integration.update!(ad_account_id: nil)
    service = instance_double(Facebook::MetaService)
    get admin_meta_integrations_path
    expect(response.body).to include(ad_accounts_admin_meta_integrations_path, "Consultando contas")
    allow(Facebook::MetaService).to receive(:new).with(integration.access_token).and_return(service)
    allow(service).to receive(:ad_accounts).and_return([{"account_id" => "123456", "name" => "Empresa"}])
    get ad_accounts_admin_meta_integrations_path
    expect(response.body).to include("Empresa (123456)", "meta_integration[ad_account_id]")
    expect(integration.reload.ad_account_id).to be_nil
  end

  it "preserva vínculo que não aparece na consulta e orienta ausência de contas" do
    integration.update!(ad_account_id: "123456", ad_account_name: "Atual")
    allow_any_instance_of(Facebook::MetaService).to receive(:ad_accounts).and_return([])
    get ad_accounts_admin_meta_integrations_path
    expect(response.body).to include("vínculo atual", "administrador do negócio")
    expect(integration.reload.ad_account_id).to eq("123456")
  end

  it "distingue falha de consulta de lista vazia sem expor detalhes internos" do
    integration
    allow_any_instance_of(Facebook::MetaService).to receive(:ad_accounts).and_raise(Timeout::Error, "segredo")
    get ad_accounts_admin_meta_integrations_path
    expect(response.body).to include("indisponível", "Atualizar contas")
    expect(response.body).not_to include("segredo", "não retornou contas")
  end

  it "não consulta contas de outra conexão" do
    create(:user_meta_integration, admin_user: create(:admin_user, :admin))
    expect(Facebook::MetaService).not_to receive(:new)
    get ad_accounts_admin_meta_integrations_path
    expect(response).to have_http_status(:not_found)
  end

  it "renderiza a conta conectada com páginas no workspace compartilhado" do
    page
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("META_LEADS_WEBHOOK_MODE").and_return("direct")
    allow(Meta::WebhookConfiguration).to receive(:verify_token).and_return("test-verify-token")
    allow(ENV).to receive(:[]).with("META_LEADS_DIRECT_WEBHOOK_PUBLIC_URL").and_return("https://app.saluteimoveis.com.br/webhooks/meta")

    get admin_meta_integrations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-operational-panel", "meta-integration-avatar--page")
    expect(response.body).to include("ax-record-item", "meta-integration-account", "ax-disclosure-card")
    expect(response.body).to include("Sincronizar Páginas", "Desconectar conta", page.name)
    expect(response.body).to include("Configuração do webhook", "App próprio", "https://app.saluteimoveis.com.br/webhooks/meta")
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
    expect(integration.reload.sync_status).to eq("failed")
    get admin_meta_integrations_path
    expect(response.body).to include("Falha ao colocar a sincronização na fila")
  end

  it "enfileira sincronização sem chamar a Meta durante a requisição" do
    integration
    expect(Facebook::MetaService).not_to receive(:new)
    expect { post sync_pages_admin_meta_integrations_path, as: :json }.to have_enqueued_job(MetaSyncJob).with(integration.id)
    expect(response).to have_http_status(:ok)
  end

  it "mantém o motivo anterior visível ao retornar durante uma nova tentativa" do
    integration.update!(sync_status: "processing", last_sync_error: "A Meta recusou a autorização. Reconecte sua conta.")
    2.times do
      get admin_meta_integrations_path
      expect(response.body).to include("A Meta recusou a autorização", "Reconecte sua conta")
    end
  end

  it "exibe pendências sem anunciar sucesso completo" do
    integration.update!(sync_status: "partial", sync_message: "Webhook da página: inscrição pendente.")
    get admin_meta_integrations_path
    expect(response.body).to include("Sincronização concluída com pendências", "inscrição pendente")
    expect(response.body).not_to include("Sincronização concluída com sucesso!")
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

require "rails_helper"

RSpec.describe "Admin::WhatsappInbox", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "wa-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET index" do
    it "exibe a central de atendimento" do
      WhatsappConversation.create!(contact_phone: "5547999990001", contact_name: "Maria", last_message_preview: "Olá", unread_count: 2)

      get admin_whatsapp_conversations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atendimento WhatsApp")
      expect(response.body).to include("Maria")
      expect(response.body).to include("ax-workspace-heading")
      expect(response.body).to include("wa-inbox-shell")
      expect(response.body).to include("ax-operational-panel")
      expect(response.body).to include("wa-inbox-panel--compact")
      expect(response.body).to include("wa-inbox-conversation--compact")
      expect(response.body).not_to include("wa-inbox-page__guide-note")
      expect(response.body).to include('data-wa-inbox-heading-metric="conversations"')
      expect(response.body).to include('data-wa-inbox-heading-metric="unread"')
      expect(response.body).to include('data-wa-inbox-filter-count="all"')
      expect(response.body).to include('data-wa-inbox-filter-count="unread"')
      expect(response.body).to include('data-wa-inbox-filter-count="unlinked"')
      expect(response.body).not_to include('data-wa-inbox-total-unread-badge')
      expect(response.body).not_to include(".wa-shell {")
    end

    it "pode abrir em modo foco com workspace dedicado" do
      WhatsappConversation.create!(contact_phone: "5547999990099", contact_name: "Maria", last_message_preview: "Olá")

      get admin_whatsapp_conversations_path(workspace: "focus")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ax-whatsapp-focus-workspace")
      expect(response.body).to include("Tela de operação contínua para fila, thread e resposta.")
      expect(response.body).to include("Tela cheia")
      expect(response.body).to include("Sair do foco")
      expect(response.body).to include('data-wa-workspace-target="enter"')
      expect(response.body).to include('data-wa-workspace-target="exit"')
      expect(response.body).to include('data-action="wa-workspace#enterFullscreen"')
      expect(response.body).to include('data-action="wa-workspace#exitFullscreen"')
    end

    it "mantém os links da fila no modo foco" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990028", contact_name: "Maria", last_message_preview: "Olá")

      get admin_whatsapp_conversations_path(workspace: "focus")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin_whatsapp_conversation_path(conv, workspace: "focus"))
    end
  end

  describe "GET show" do
    it "abre a conversa e zera não lidas" do
      allow(Whatsapp::ThreadBroadcaster).to receive(:queue_refreshed)
      conv = WhatsappConversation.create!(contact_phone: "5547999990002", unread_count: 3)
      conv.messages.create!(direction: "inbound", body: "Tem disponível?", status: "delivered")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tem disponível?")
      expect(response.body).to include("wa-inbox-composer")
      expect(response.body).not_to include("data-wa-thread-url-value")
      expect(response.body).to include("wa-inbox-composer--compact")
      expect(response.body).to include("wa-inbox-thread__workspace--compact")
      expect(response.body).to include("multipart/form-data")
      expect(response.body).to include("Responder no CRM")
      expect(response.body).to include("Sem lead vinculado")
      expect(conv.reload.unread_count).to eq(0)
      expect(Whatsapp::ThreadBroadcaster).to have_received(:queue_refreshed).with(conv)
    end

    it "renderiza composer compacto no workspace dedicado" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990077")
      conv.messages.create!(direction: "outbound", body: "Mensagem compacta", status: "sent")

      get admin_whatsapp_conversation_path(conv, workspace: "focus")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("wa-inbox-composer wa-inbox-composer--compact")
      expect(response.body).to include("Mensagem compacta")
    end

    it "renderiza separador de dia e agrupamento para mensagens sequenciais" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990062")
      first = conv.messages.create!(direction: "outbound", body: "Primeira", status: "sent", created_at: Time.zone.local(2026, 6, 30, 10, 0, 0))
      conv.messages.create!(direction: "outbound", body: "Segunda", status: "sent", created_at: first.created_at + 3.minutes)

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("wa-inbox-thread__day-separator")
      expect(response.body).to include("wa-inbox-bubble-row--grouped")
      expect(response.body).to include("wa-inbox-bubble--continued")
      expect(response.body).to include("wa-inbox-bubble--group-tail")
      expect(response.body).to include("wa-inbox-bubble__time--muted")
    end

    it "renderiza imagem anexada na thread" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990008")
      message = conv.messages.create!(direction: "outbound", msg_type: "image", body: "Foto do imóvel", status: "sent")
      message.media_file.attach(io: StringIO.new("fake-image"), filename: "foto.jpg", content_type: "image/jpeg")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("wa-inbox-media--image")
      expect(response.body).to include("Foto do imóvel")
      expect(response.body).to include("foto.jpg")
      expect(response.body).to include('data-fancybox-type="inline"')
      expect(response.body).to include('data-turbo="false"')
      expect(response.body).to include('data-admin-navigation-ignore="true"')
      expect(response.body).to include("wa-fancybox-visual--image")
      expect(response.body).to include("Baixar")
    end

    it "renderiza documento com componente de anexo reutilizável" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990013")
      message = conv.messages.create!(direction: "inbound", msg_type: "document", status: "delivered")
      message.media_file.attach(io: StringIO.new("%PDF-1.7 fake"), filename: "proposta.pdf", content_type: "application/pdf")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("wa-inbox-media-card--document")
      expect(response.body).to include("wa-inbox-media-card--message")
      expect(response.body).to include("proposta.pdf")
      expect(response.body).to include("PDF")
      expect(response.body).to include('data-fancybox-type="inline"')
      expect(response.body).to include('data-turbo="false"')
      expect(response.body).to include('data-admin-navigation-ignore="true"')
      expect(response.body).to include("wa-fancybox-document")
      expect(response.body).to include("Baixar")
    end

    it "renderiza áudio com nome do arquivo para contexto operacional" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990041")
      message = conv.messages.create!(direction: "outbound", msg_type: "audio", status: "sent")
      message.media_file.attach(io: StringIO.new("fake-audio"), filename: "ligacao.mp3", content_type: "audio/mpeg")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      message_node = Nokogiri::HTML(response.body).at_css(%([data-message-id="#{message.id}"]))
      expect(message_node).to be_present
      expect(message_node.to_html).to include("wa-inbox-bubble__surface")
      expect(message_node.to_html).to include("wa-inbox-bubble--compact")
      expect(response.body).to include("wa-audio-preview")
      expect(response.body).to include("wa-audio-preview--message")
      expect(response.body).to include("ligacao.mp3")
      expect(response.body).to include('data-controller="wa-audio-preview"')
      expect(response.body).to include("wa-audio-preview__track")
      expect(response.body).to include("wa-audio-preview__summary")
      expect(response.body).to include('data-turbo="false"')
      expect(response.body).to include('data-admin-navigation-ignore="true"')
      expect(response.body).to include("data-wa-audio-preview-target=\"current\"")
      expect(response.body).to include("data-wa-audio-preview-target=\"duration\"")
      expect(response.body).to include('preload="none"')
      expect(response.body).to include("data-src=")
      expect(response.body).to include('data-fancybox-type="inline"')
      expect(response.body).to include("wa-fancybox-audio")
      expect(response.body).to include('data-inline-viewer-media="true"')
      expect(response.body).to include('class="wa-fancybox-audio__player"')
      expect(response.body).to include('preload="none"')
      expect(response.body).not_to include("autoplay")
    end

    it "renderiza video como preview clicável no viewer inline" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990044")
      message = conv.messages.create!(direction: "outbound", msg_type: "video", body: "Tour em vídeo", status: "sent")
      message.media_file.attach(io: StringIO.new("fake-video"), filename: "tour.mp4", content_type: "video/mp4")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("wa-inbox-media-frame--video")
      expect(response.body).to include("wa-inbox-media--video-link")
      expect(response.body).to include("wa-inbox-bubble__surface")
      expect(response.body).to include('data-fancybox-type="inline"')
      expect(response.body).to include('data-turbo="false"')
      expect(response.body).to include('data-admin-navigation-ignore="true"')
      expect(response.body).to include("wa-fancybox-visual--video")
    end

    it "renderiza imagem com a mesma superfície visual dos demais cards de mídia" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990049")
      message = conv.messages.create!(direction: "outbound", msg_type: "image", body: "Fachada", status: "sent")
      message.media_file.attach(io: StringIO.new("fake-image"), filename: "fachada.jpg", content_type: "image/jpeg")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("wa-inbox-media-frame--image")
      expect(response.body).to include("wa-inbox-media--image-link")
      expect(response.body).to include('data-fancybox-type="inline"')
    end

    it "expõe ações comerciais quando a conversa tem lead vinculado" do
      lead = create(:lead, tenant: admin.tenant, name: "Lead Comercial")
      conv = WhatsappConversation.create!(contact_phone: "5547999990017", lead: lead)

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lead no CRM")
      expect(response.body).to include("Tarefa")
      expect(response.body).to include("Agendar")
      expect(response.body).to include("Proposta")
      expect(response.body).to include(admin_lead_path(lead))
    end

    it "bloqueia ações comerciais quando ainda não existe lead vinculado" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990018")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sem lead vinculado")
      expect(response.body).not_to include("whatsappInboxTask")
      expect(response.body).not_to include("Agendar")
    end

    it "não renderiza CTA externo quebrado quando a conversa usa apenas BSUID" do
      conv = WhatsappConversation.create!(business_scoped_user_id: "wamid.user.123", contact_name: "Meta User")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Meta User")
      expect(response.body).to include("Sem lead")
      expect(response.body).not_to include("href=\"\"")
      expect(response.body).not_to include("wa.me")
    end
  end

  describe "GET media" do
    it "serve mídia anexada pelo app" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990011")
      message = conv.messages.create!(direction: "inbound", msg_type: "image", status: "delivered")
      message.media_file.attach(io: StringIO.new("fake-image"), filename: "foto.jpg", content_type: "image/jpeg")

      get message_media_admin_whatsapp_conversation_path(conv, message_id: message.id)

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/rails/active_storage/")
    end

    it "faz proxy da mídia remota da Meta quando ainda não há attachment local" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990012")
      message = conv.messages.create!(direction: "inbound", msg_type: "document", media_url: "https://graph.example.test/media/1", status: "delivered")
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:download_media).with("https://graph.example.test/media/1").and_return(
        ok: true,
        body: "%PDF-1.7 fake",
        content_type: "application/pdf"
      )

      get message_media_admin_whatsapp_conversation_path(conv, message_id: message.id)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end
  end

  describe "POST send_message" do
    it "cria mensagem outbound, registra na timeline e enfileira envio" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      allow(Whatsapp::ThreadBroadcaster).to receive(:message_created)
      lead = create(:lead)
      conv = WhatsappConversation.create!(contact_phone: "5547999990003", lead: lead)

      expect {
        post send_message_admin_whatsapp_conversation_path(conv), params: { body: "Olá, posso ajudar?" }
      }.to change {
        WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").count
      }.by(1)

      expect(response).to redirect_to(admin_whatsapp_conversation_path(conv))

      msg = WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").order(:created_at).last
      expect(msg.body).to eq("Olá, posso ajudar?")
      expect(msg.status).to eq("pending")
      expect(Whatsapp::SendMessageJob).to have_received(:perform_later).with(msg.id, tenant_id: msg.tenant_id)
      expect(Whatsapp::ThreadBroadcaster).to have_received(:message_created).with(msg)
      expect(lead.activities.where(kind: "whatsapp_out").count).to eq(1)
    end

    it "respeita return_to para continuar no detalhe do lead" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      lead = create(:lead)
      conv = WhatsappConversation.create!(contact_phone: "5547999990023", lead: lead)

      post send_message_admin_whatsapp_conversation_path(conv), params: {
        body: "Mensagem no lead",
        return_to: admin_lead_path(lead)
      }

      expect(response).to redirect_to(admin_lead_path(lead))
    end

    it "preserva o modo foco ao responder na conversa dedicada" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      conv = WhatsappConversation.create!(contact_phone: "5547999990029")

      post send_message_admin_whatsapp_conversation_path(conv), params: {
        body: "Mensagem no foco",
        return_to: admin_whatsapp_conversation_path(conv, workspace: "focus")
      }

      expect(response).to redirect_to(admin_whatsapp_conversation_path(conv, workspace: "focus"))
    end

    it "cria mensagem outbound com anexo" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      conv = WhatsappConversation.create!(contact_phone: "5547999990007")

      expect {
        post send_message_admin_whatsapp_conversation_path(conv), params: {
          body: "Segue documento",
          media_file: fixture_file_upload("template-video.mp4", "video/mp4")
        }
      }.to change {
        WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").count
      }.by(1)

      msg = WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").order(:created_at).last
      expect(msg.msg_type).to eq("video")
      expect(msg.media_file).to be_attached
      expect(response).to redirect_to(admin_whatsapp_conversation_path(conv))
    end

    it "rejeita arquivo fora dos formatos aceitos pela Cloud API" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      conv = WhatsappConversation.create!(contact_phone: "5547999990031")

      expect {
        post send_message_admin_whatsapp_conversation_path(conv), params: {
          body: "Segue arquivo",
          media_file: fixture_file_upload("template-video.mp4", "application/zip")
        }
      }.not_to change {
        WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").count
      }

      expect(response).to redirect_to(admin_whatsapp_conversation_path(conv))
      expect(flash[:alert]).to include("Formato não suportado")
    end

    it "responde json para envio assíncrono sem redirect" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      conv = WhatsappConversation.create!(contact_phone: "5547999990040")

      post send_message_admin_whatsapp_conversation_path(conv),
           params: { body: "Mensagem assíncrona" },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["ok"]).to eq(true)
      expect(data["body"]).to eq("Mensagem assíncrona")
      expect(data["direction"]).to eq("outbound")
      expect(data["html"]).to include("Mensagem assíncrona")
      expect(data["context_html"]).to include("Última atividade")
      expect(data.dig("queue", "html")).to include("Mensagem assíncrona")
    end

    it "responde erro json para envio inválido" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      conv = WhatsappConversation.create!(contact_phone: "5547999990041")

      post send_message_admin_whatsapp_conversation_path(conv),
           params: { body: "" },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      data = JSON.parse(response.body)
      expect(data["ok"]).to eq(false)
      expect(data["error"]).to include("Escreva uma mensagem")
    end

    it "bloqueia combinação ambígua entre modelo aprovado e arquivo" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      conv = WhatsappConversation.create!(contact_phone: "5547999990014")
      WhatsappTemplate.create!(tenant: admin.tenant, name: "modelo_aprovado", language: "pt_BR", status: "APPROVED", body: "Oi")

      expect {
        post send_message_admin_whatsapp_conversation_path(conv), params: {
          template_name: "modelo_aprovado",
          media_file: fixture_file_upload("template-video.mp4", "video/mp4")
        }
      }.not_to change {
        WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").count
      }

      expect(response).to redirect_to(admin_whatsapp_conversation_path(conv))
      expect(flash[:alert]).to eq("Escolha entre modelo aprovado ou arquivo.")
    end
  end

  describe "GET messages (polling json)" do
    it "não expõe mais endpoint de polling da thread" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990004", unread_count: 2)

      expect {
        Rails.application.routes.recognize_path("/admin/atendimento/whatsapp/#{conv.id}/messages", method: :get)
      }.to raise_error(ActionController::RoutingError)
    end
  end
end

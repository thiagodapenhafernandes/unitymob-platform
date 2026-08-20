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
      expect(response.body).to include("wa-inbox-shell")
      expect(response.body).to include("wa-inbox-panel--list")
      expect(response.body).to include("wa-inbox-panel--thread")
      expect(response.body).to include("wa-inbox-panel--compact")
      expect(response.body).to include("wa-inbox-conversation--compact")
      expect(response.body).to include("whatsapp_inbox_refresh")
      expect(response.body).to include("wa-inbox-conversation__avatar")
      expect(response.body).to include(">M</span>")
      expect(response.body).not_to include("wa-inbox-conversation__card ax-record-item")
      expect(response.body).not_to include("wa-inbox-page__guide-note")
      expect(response.body).to include('data-wa-inbox-heading-metric="conversations"')
      expect(response.body).to include('data-wa-inbox-heading-metric="unread"')
      expect(response.body).to include('data-wa-inbox-filter-count="all"')
      expect(response.body).to include('data-wa-inbox-filter-count="unread"')
      expect(response.body).to include('data-wa-inbox-filter-count="unlinked"')
      expect(response.body).to include('turbo-frame id="wa-thread"')
      expect(response.body).to include('id="wa-inbox-queue"')
      expect(response.body).to include("data-turbo-permanent")
      expect(response.body).not_to include('data-wa-inbox-total-unread-badge')
      expect(response.body).not_to include(".wa-shell {")
    end

    it "mantém fila fora do frame e links mirando o detalhe" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990038", contact_name: "Maria", last_message_preview: "Olá")

      get admin_whatsapp_conversations_path

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      frame = document.at_css("turbo-frame#wa-thread")
      queue = document.at_css("#wa-inbox-queue")
      conversation = document.at_css(%(.wa-inbox-conversation[data-conversation-id="#{conv.id}"]))

      expect(frame).to be_present
      expect(queue).to be_present
      expect(frame.css("#wa-inbox-queue")).to be_empty
      expect(conversation["data-turbo-frame"]).to eq("wa-thread")
      expect(conversation["data-turbo-action"]).to eq("advance")
      expect(conversation["data-action"]).to include("click->wa-queue#select")
      expect(conversation["data-conversation-default-href"]).to eq(admin_whatsapp_conversation_path(conv))
      expect(conversation["data-unread"]).to eq("false")
      expect(conversation["data-lead"]).to eq("false")
      expect(conversation["data-search"]).to include("maria")
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

    it "filtra conversas que aguardam resposta da equipe" do
      pending = WhatsappConversation.create!(contact_phone: "5547999990048", contact_name: "Cliente Pendente", status: "open", unread_count: 1, last_message_preview: "Ainda quero visitar")
      answered = WhatsappConversation.create!(contact_phone: "5547999990047", contact_name: "Cliente Respondido", status: "open", last_message_preview: "Obrigado")

      pending.messages.create!(direction: "outbound", body: "Olá", created_at: 2.hours.ago, updated_at: 2.hours.ago)
      pending.messages.create!(direction: "inbound", body: "Ainda quero visitar", created_at: 1.hour.ago, updated_at: 1.hour.ago)
      answered.messages.create!(direction: "inbound", body: "Tenho interesse", created_at: 2.hours.ago, updated_at: 2.hours.ago)
      answered.messages.create!(direction: "outbound", body: "Vamos agendar", created_at: 1.hour.ago, updated_at: 1.hour.ago)

      get admin_whatsapp_conversations_path(filter: "pending_reply")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cliente Pendente")
      expect(response.body).not_to include("Cliente Respondido")
      expect(response.body).to include('data-wa-queue-initial-filter-value="pending_reply"')
      expect(response.body).to include('data-pending-reply="true"')
      expect(response.body).to include("Aguardando resposta")
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
      expect(response.body).to include("Sem lead")
      expect(response.body).to include('turbo-frame id="wa-thread"')
      expect(conv.reload.unread_count).to eq(0)
      expect(Whatsapp::ThreadBroadcaster).to have_received(:queue_refreshed).with(conv)
    end

    it "responde ao Turbo Frame sem renderizar a fila inteira" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990039", contact_name: "Maria Frame")
      conv.messages.create!(direction: "inbound", body: "Mensagem do frame", status: "delivered")

      get admin_whatsapp_conversation_path(conv), headers: { "Turbo-Frame" => "wa-thread" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('turbo-frame id="wa-thread"')
      expect(response.body).to include("Mensagem do frame")
      expect(response.body).not_to include('id="wa-inbox-queue"')
      expect(response.body).not_to include("wa-inbox-panel--list")
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
      expect(response.body).to include('data-fancybox-type="inline"')
      expect(response.body).to include('data-turbo="false"')
      expect(response.body).to include('data-admin-navigation-ignore="true"')
      expect(response.body).to include("wa-fancybox-visual--image")
      expect(response.body).to include("Baixar")
    end

    it "renderiza template oficial com imagem no formato de cartão WhatsApp" do
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(status: "connected", waba_id: "waba-template-card", phone_number_id: "phone-template-card", access_token: "token-template-card")
      WhatsappTemplate.create!(
        tenant: admin.tenant,
        waba_id: integration.waba_id,
        name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
        language: "pt_BR",
        status: "APPROVED",
        category: "MARKETING",
        template_type: "text",
        footer_text: "Atendimento",
        body: "Oi! Aqui é {{1}}, da {{2}}."
      )
      conv = WhatsappConversation.create!(tenant: admin.tenant, contact_phone: "5547999990074", contact_name: "Cliente Template")
      message = conv.messages.create!(
        tenant: admin.tenant,
        direction: "outbound",
        msg_type: "template",
        template_name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
        body: "Oi! Aqui é Thiago, da Conexão BC.",
        status: "sent"
      )
      message.media_file.attach(io: StringIO.new("fake-image"), filename: "template.jpg", content_type: "image/jpeg")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("wa-inbox-bubble--template-card")
      expect(response.body).to include("wa-inbox-bubble__body--template")
      expect(response.body).to include("wa-inbox-bubble__template-footer")
      expect(response.body).to include("Atendimento")
      expect(response.body).not_to include("modelo lead_activation_default")
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
      expect(response.body).to include('data-inline-viewer-media="true"')
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
      expect(response.body).to include("Agendar visita")
      expect(response.body).to include("wa-inbox-thread__schedule-button")
      expect(response.body).to include(admin_lead_path(lead))
    end

    it "bloqueia ações comerciais quando ainda não existe lead vinculado" do
      conv = WhatsappConversation.create!(contact_phone: "5547999990018")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sem lead")
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

    it "mantém modelos aprovados fora do atalho de apresentação" do
      create(:whatsapp_business_integration,
             tenant: admin.tenant,
             connected_by_admin_user: admin,
             presentation_enabled: true)
      PresentationCard.ensure_system_default_for(admin.tenant)
      WhatsappTemplate.create!(
        tenant: admin.tenant,
        name: "modelo_survey_aprovado",
        language: "pt_BR",
        status: "APPROVED",
        body: "Oi"
      )
      conv = WhatsappConversation.create!(contact_phone: "5547999990050")

      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      quick_replies = document.at_css('[data-controller="quick-replies"] .wa-composer-popover')

      expect(quick_replies).to be_present
      expect(quick_replies.text).to include("Apresentação")
      expect(quick_replies.text).to include("Meus cartões")
      expect(quick_replies.text).not_to include("Modelos aprovados")
      expect(quick_replies.text).not_to include("modelo_survey_aprovado")
      expect(quick_replies.at_css(".wa-composer-popover__icon--template")).to be_nil
    end

    it "renderiza avatar de apresentação para corretor dono do lead quando a mensagem não tem attachment local" do
      profile = admin.tenant.profiles.create!(
        name: "Corretor dono do lead",
        axis: "vertical",
        permissions: {
          "leads" => { "view" => true, "scope" => "own" },
          "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" }
        }
      )
      broker = create(:admin_user, tenant: admin.tenant, profile: profile)
      broker.avatar.attach(io: StringIO.new("fake-avatar"), filename: "corretor.jpg", content_type: "image/jpeg")
      card = PresentationCard.create!(
        tenant: admin.tenant,
        admin_user: broker,
        label: "Meu cartão",
        greeting: "Oi, sou {nome}",
        use_photo: true,
        active: true
      )
      lead = create(:lead, tenant: admin.tenant, admin_user: broker, phone: "5547999990051")
      conv = WhatsappConversation.create!(tenant: admin.tenant, contact_phone: lead.phone, lead: lead)
      conv.messages.create!(
        direction: "outbound",
        msg_type: "image",
        body: "Oi, sou o corretor",
        admin_user: broker,
        presentation_card: card,
        status: "sent"
      )

      sign_in broker
      get admin_whatsapp_conversation_path(conv)

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      image = document.at_css(".wa-inbox-media--image")

      expect(image).to be_present
      expect(image["src"]).to include("/rails/active_storage/blobs")
      expect(image["src"]).not_to include(message_media_admin_whatsapp_conversation_path(conv, message_id: conv.messages.last.id))
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

    it "serve mídia da conversa quando o acesso vem pelo contexto do lead" do
      profile = admin.tenant.profiles.create!(
        name: "Midia via lead",
        axis: "vertical",
        permissions: {
          "leads" => { "view" => true, "scope" => "all" },
          "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" }
        }
      )
      user = create(:admin_user, tenant: admin.tenant, profile: profile)
      lead_owner = create(:admin_user, tenant: admin.tenant)
      lead = create(:lead, tenant: admin.tenant, admin_user: lead_owner, phone: "5547999990044")
      conv = WhatsappConversation.create!(tenant: admin.tenant, contact_phone: lead.phone, lead: lead)
      message = conv.messages.create!(direction: "outbound", msg_type: "audio", status: "failed")
      message.media_file.attach(io: StringIO.new("fake-audio"), filename: "audio.webm", content_type: "audio/webm")

      sign_in user

      get message_media_admin_whatsapp_conversation_path(conv, message_id: message.id)

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/rails/active_storage/")
    end

    it "serve avatar de apresentação para corretor dono quando não há attachment local" do
      profile = admin.tenant.profiles.create!(
        name: "Midia apresentação via lead",
        axis: "vertical",
        permissions: {
          "leads" => { "view" => true, "scope" => "own" },
          "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" }
        }
      )
      broker = create(:admin_user, tenant: admin.tenant, profile: profile)
      broker.avatar.attach(io: StringIO.new("fake-avatar"), filename: "corretor.jpg", content_type: "image/jpeg")
      card = PresentationCard.create!(
        tenant: admin.tenant,
        admin_user: broker,
        label: "Meu cartão",
        greeting: "Oi, sou {nome}",
        use_photo: true,
        active: true
      )
      lead = create(:lead, tenant: admin.tenant, admin_user: broker, phone: "5547999990052")
      conv = WhatsappConversation.create!(tenant: admin.tenant, contact_phone: lead.phone, lead: lead)
      message = conv.messages.create!(
        direction: "outbound",
        msg_type: "image",
        admin_user: broker,
        presentation_card: card,
        status: "sent"
      )

      sign_in broker

      get message_media_admin_whatsapp_conversation_path(conv, message_id: message.id)

      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to include("/rails/active_storage/")
    end
  end

  describe "POST send_message" do
    it "cria mensagem outbound, registra na timeline e enfileira envio" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      allow_any_instance_of(Whatsapp::CloudClient).to receive(:upload_message_media).and_return({ ok: true, media_id: "uploaded-template-media" })
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

    it "envia cartão de apresentação com foto como imagem no desktop" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      create(:whatsapp_business_integration,
             tenant: admin.tenant,
             connected_by_admin_user: admin,
             presentation_enabled: true,
             allow_photo_presentation: true)
      admin.avatar.attach(io: StringIO.new("fake-avatar"), filename: "corretor.jpg", content_type: "image/jpeg")
      card = PresentationCard.create!(
        tenant: admin.tenant,
        admin_user: admin,
        label: "Meu cartão",
        greeting: "Oi, sou {nome}",
        use_photo: true,
        active: true
      )
      conv = WhatsappConversation.create!(contact_phone: "5547999990053")

      expect {
        post send_message_admin_whatsapp_conversation_path(conv), params: {
          body: card.message_body_for(admin),
          presentation_card_id: card.id
        }
      }.to change {
        WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").count
      }.by(1)

      msg = WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").order(:created_at).last
      expect(msg.msg_type).to eq("image")
      expect(msg.presentation_card_id).to eq(card.id)
      expect(msg.media_file).to be_attached
      expect(msg.media_file.blob).to eq(admin.avatar.blob)
      expect(response).to redirect_to(admin_whatsapp_conversation_path(conv))
    end

    it "envia o template oficial de apresentação mesmo com apresentação obrigatória pendente" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(
        status: "connected",
        waba_id: "waba-official-presentation",
        phone_number_id: "phone-official-presentation",
        access_token: "token-official-presentation",
        presentation_enabled: true,
        require_presentation: true
      )
      lead = create(:lead, tenant: admin.tenant, phone: "5547999990054")
      conv = WhatsappConversation.create!(tenant: admin.tenant, contact_phone: lead.phone, lead: lead)
      template = WhatsappTemplate.create!(
        tenant: admin.tenant,
        waba_id: integration.waba_id,
        name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
        language: "pt_BR",
        status: "APPROVED",
        category: "MARKETING",
        template_type: "text",
        header_format: "image",
        header_media_handle: "header-handle",
        body: "Oi! Aqui é {{1}}, da {{2}}.",
        components: [
          { "type" => "HEADER", "format" => "IMAGE", "example" => { "header_handle" => ["header-handle"] } },
          { "type" => "BODY", "text" => "Oi! Aqui é {{1}}, da {{2}}." }
        ]
      )
      template.header_media_file.attach(io: StringIO.new("fake-template-image"), filename: "template.jpg", content_type: "image/jpeg")

      expect {
        post send_message_admin_whatsapp_conversation_path(conv), params: {
          template_name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME
        }
      }.to change {
        WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").count
      }.by(1).and change {
        lead.activities.where(kind: "presentation_sent").count
      }.by(1)

      msg = WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").order(:created_at).last
      expect(response).to redirect_to(admin_whatsapp_conversation_path(conv))
      expect(msg.msg_type).to eq("template")
      expect(msg.template_name).to eq(Whatsapp::LeadActivationTemplate::TEMPLATE_NAME)
      expect(msg.media_file).to be_attached
      expect(msg.media_file.blob).to eq(template.header_media_file.blob)
      expect(msg.body).to include(admin.name, admin.tenant.name)
      expect(msg.template_components).to include(
        "type" => "header",
        "parameters" => [
          { "type" => "image", "image" => { "id" => "uploaded-template-media" } }
        ]
      )
      expect(msg.template_components).to include(
        "type" => "body",
        "parameters" => [
          { "type" => "text", "text" => admin.name },
          { "type" => "text", "text" => admin.tenant.name }
        ]
      )
      expect(Whatsapp::SendMessageJob).to have_received(:perform_later).with(msg.id, tenant_id: msg.tenant_id)
      expect(lead.activities.where(kind: "presentation_sent").last.metadata).to include(
        "template_name" => Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
        "format" => "template"
      )
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

    it "envia pelo composer do lead quando a conversa esta fora do recorte do inbox" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      profile = admin.tenant.profiles.create!(
        name: "Atendimento via lead",
        axis: "vertical",
        permissions: {
          "leads" => { "view" => true, "scope" => "all" },
          "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" }
        }
      )
      user = create(:admin_user, tenant: admin.tenant, profile: profile)
      lead_owner = create(:admin_user, tenant: admin.tenant)
      lead = create(:lead, tenant: admin.tenant, admin_user: lead_owner, phone: "5547999990042")
      conv = WhatsappConversation.create!(tenant: admin.tenant, contact_phone: lead.phone, lead: lead)

      sign_in user

      expect {
        post send_message_admin_whatsapp_conversation_path(conv),
             params: { body: "Mensagem pelo lead", lead_id: lead.id },
             headers: { "ACCEPT" => "application/json" }
      }.to change {
        WhatsappMessage.unscoped.where(whatsapp_conversation_id: conv.id, direction: "outbound").count
      }.by(1)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["ok"]).to eq(true)
      expect(data["body"]).to eq("Mensagem pelo lead")
    end

    it "vincula conversa encontrada por telefone ao lead do composer antes de enviar" do
      allow_any_instance_of(Admin::WhatsappInboxController).to receive(:verified_request?).and_return(true)
      allow(Whatsapp::SendMessageJob).to receive(:perform_later)
      profile = admin.tenant.profiles.create!(
        name: "Lead all WhatsApp own",
        axis: "vertical",
        permissions: {
          "leads" => { "view" => true, "scope" => "all" },
          "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" }
        }
      )
      user = create(:admin_user, tenant: admin.tenant, profile: profile)
      lead = create(:lead, tenant: admin.tenant, phone: "5547999990043")
      conv = WhatsappConversation.create!(tenant: admin.tenant, contact_phone: lead.phone)

      sign_in user

      post send_message_admin_whatsapp_conversation_path(conv),
           params: { body: "Agora vincula", lead_id: lead.id },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(conv.reload.lead_id).to eq(lead.id)
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

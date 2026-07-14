require "rails_helper"

RSpec.describe "Admin::WhatsappTemplates", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "wa-template-#{SecureRandom.hex(6)}@salute.test") }

  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET index" do
    it "lista templates e acoes de campanha para aprovados" do
      sender = create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: "waba-listagem")
      admin.tenant.whatsapp_templates.create!(name: "convite", language: "pt_BR", status: "APPROVED", category: "MARKETING", body: "Olá", waba_id: sender.waba_id)

      get admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Templates WhatsApp")
      expect(response.body).to include("convite")
      expect(response.body).to include("Criar campanha")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("a.whatsapp-template-selector__option[aria-current='true']")).to be_present
      expect(document.at_css("table caption")&.text).to include("Templates da WABA selecionada")
      expect(document.css("table th[scope='col']").size).to eq(6)
      campaign_action = document.at_css("a.ax-btn--primary[href*='new_campaign']")
      expect(campaign_action).to be_present
      expect(campaign_action["style"]).to be_nil
    end

    it "pede selecao do numero antes de listar templates" do
      create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: "waba-selecao")

      get admin_whatsapp_templates_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Número / WABA")
      expect(response.body).not_to include("<table")
    end


    it "usa os estados vazios compartilhados para numeros e templates" do
      get admin_whatsapp_templates_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nenhum número ativo cadastrado", "ax-empty-state")

      sender = create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: "waba-vazia")
      get admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nenhum template encontrado", "Ajuste os filtros ou sincronize novamente")
    end

    it "nao lista o numero fixo das notificacoes como numero de campanha" do
      WhatsappBusinessIntegration.current(admin.tenant).update!(
        status: "connected",
        phone_number_id: "phone-notificacoes",
        waba_id: "waba-notificacoes",
        access_token: "token"
      )
      create(:whatsapp_sender_number, tenant: admin.tenant, phone_number_id: "phone-notificacoes", display_phone_number: "554721228669", waba_id: "waba-notificacoes", label: "Notificações")
      create(:whatsapp_sender_number, tenant: admin.tenant, phone_number_id: "phone-campanhas", display_phone_number: "554733111067", waba_id: "waba-campanhas", label: "Campanhas")

      get admin_whatsapp_templates_path

      expect(response.body).to include("Campanhas")
      expect(response.body).to include("554733111067")
      expect(response.body).not_to include("554721228669")
    end
  end

  describe "GET new" do
    it "renderiza escolha de tipos de template" do
      get new_admin_whatsapp_template_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Mensagem de Texto")
      expect(response.body).to include("Media Card Carousel")
      expect(response.body).to include("Template com Flow")
    end

    it "inclui video e exemplos dinamicos no template de texto" do
      get new_admin_whatsapp_template_path(template_type: "text")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cabeçalho")
      expect(response.body).to include("Vídeo")
      expect(response.body).to include("Mídia de exemplo")
      expect(response.body).to include("Adicionar exemplo")
      expect(response.body).not_to include("Handle da mídia na Meta")
    end

    it "renderiza editor completo de carousel" do
      get new_admin_whatsapp_template_path(template_type: "carousel")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cards do carrossel")
      expect(response.body).to include("Adicionar card")
      expect(response.body).to include("Mídia do card")
      expect(response.body).not_to include("Ainda está bloqueado")
    end

    it "renderiza editor completo de flow" do
      get new_admin_whatsapp_template_path(template_type: "flow")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Conexão com Flow")
      expect(response.body).to include("ID do Flow na Meta")
      expect(response.body).to include("Ação do Flow")
      expect(response.body).not_to include("Ainda está bloqueado")
    end
  end

  describe "POST create" do
    it "envia template de texto com midia automatizada para aprovacao" do
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:upload_template_media).and_return({ ok: true, handle: "media-handle" })
      allow(client).to receive(:create_template).and_return({ ok: true, data: { "id" => "123", "status" => "PENDING" } })
      media_file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/template-video.mp4"), "video/mp4")

      post admin_whatsapp_templates_path, params: {
        whatsapp_template: {
          name: "convite_video",
          language: "pt_BR",
          category: "MARKETING",
          template_type: "text",
          body: "Olá {{1}}",
          header_format: "video",
          header_media_file: media_file,
          example_values: ["Maria"],
          buttons: {
            "0" => { kind: "quick_reply", text: "Saiba mais" }
          }
        }
      }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/admin/whatsapp/templates?whatsapp_sender_number_id=")
      template = WhatsappTemplate.find_by!(name: "convite_video")
      expect(template.status).to eq("PENDING")
      expect(template.meta_id).to eq("123")
      expect(template.header_media_handle).to eq("media-handle")
      expect(template.components.first).to include("type" => "HEADER", "format" => "VIDEO")
    end

    it "normaliza o nome antes de enviar para a Meta" do
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:create_template).and_return({ ok: true, data: { "id" => "name-123", "status" => "PENDING" } })

      post admin_whatsapp_templates_path, params: {
        whatsapp_template: {
          name: "Campanha Fake",
          language: "pt_BR",
          category: "MARKETING",
          template_type: "text",
          body: "Olá",
          header_format: "none"
        }
      }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/admin/whatsapp/templates?whatsapp_sender_number_id=")
      expect(client).to have_received(:create_template).with(hash_including(name: "campanha_fake"))
      expect(WhatsappTemplate.find_by!(name: "campanha_fake").status).to eq("PENDING")
    end

    it "mostra erro retornado pela Meta no formulario" do
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:create_template).and_return({
        ok: false,
        status: 400,
        error: "Invalid parameter: o nome do modelo já existe na Meta.",
        meta_error: { code: 100, trace_id: "trace-1" }
      })

      post admin_whatsapp_templates_path, params: {
        whatsapp_template: {
          name: "template_repetido",
          language: "pt_BR",
          category: "MARKETING",
          template_type: "text",
          body: "Olá",
          header_format: "none"
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Não foi possível enviar este modelo para aprovação")
      expect(response.body).to include("Invalid parameter: o nome do modelo já existe na Meta.")
    end

    it "envia carousel com upload automatico das midias dos cards" do
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:upload_template_media).and_return(
        { ok: true, handle: "card-handle-1" },
        { ok: true, handle: "card-handle-2" }
      )
      allow(client).to receive(:create_template).and_return({ ok: true, data: { "id" => "carousel-123", "status" => "PENDING" } })
      card_1_file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/template-video.mp4"), "video/mp4")
      card_2_file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/template-video.mp4"), "video/mp4")

      post admin_whatsapp_templates_path, params: {
        whatsapp_template: {
          name: "carrossel_lancamento",
          language: "pt_BR",
          category: "MARKETING",
          template_type: "carousel",
          body: "Escolha uma opção.",
          carousel_card_media_files: [card_1_file, card_2_file],
          carousel_cards: {
            "0" => { media_type: "video", text: "Card 1", button_text: "Ver", button_url: "https://example.com/1" },
            "1" => { media_type: "video", text: "Card 2", button_text: "Abrir", button_url: "https://example.com/2" }
          }
        }
      }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/admin/whatsapp/templates?whatsapp_sender_number_id=")
      template = WhatsappTemplate.find_by!(name: "carrossel_lancamento")
      expect(template.meta_id).to eq("carousel-123")
      expect(template.carousel_cards.map { |card| card["media_handle"] }).to eq(%w[card-handle-1 card-handle-2])
      expect(template.components.last["type"]).to eq("CAROUSEL")
      expect(template.components.last["cards"].size).to eq(2)
    end

    it "envia template com Flow para aprovacao" do
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:create_template).and_return({ ok: true, data: { "id" => "flow-123", "status" => "PENDING" } })

      post admin_whatsapp_templates_path, params: {
        whatsapp_template: {
          name: "flow_agendamento",
          language: "pt_BR",
          category: "UTILITY",
          template_type: "flow",
          body: "Toque para agendar.",
          footer_text: "Leva menos de um minuto.",
          flow_config: {
            flow_id: "123456789",
            button_text: "Agendar",
            action: "navigate",
            screen: "APPOINTMENT"
          }
        }
      }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/admin/whatsapp/templates?whatsapp_sender_number_id=")
      template = WhatsappTemplate.find_by!(name: "flow_agendamento")
      expect(template.meta_id).to eq("flow-123")
      expect(template.components.last["buttons"].first).to include(
        "type" => "FLOW",
        "text" => "Agendar",
        "flow_id" => "123456789"
      )
    end
  end

  describe "POST upload_media" do
    it "faz pre-upload da midia na Meta e retorna o handle" do
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
      allow(client).to receive(:upload_template_media).and_return({ ok: true, handle: "handle-preview" })
      media_file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/template-video.mp4"), "video/mp4")

      post upload_media_admin_whatsapp_templates_path, params: {
        media_type: "video",
        file: media_file
      }, as: :multipart

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("handle" => "handle-preview")
      expect(client).to have_received(:upload_template_media).with(
        hash_including(content_type: "video/mp4", file_name: "template-video.mp4")
      )
    end

    it "retorna erro quando a midia nao corresponde ao tipo selecionado" do
      media_file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/template-video.mp4"), "video/mp4")

      post upload_media_admin_whatsapp_templates_path, params: {
        media_type: "image",
        file: media_file
      }, as: :multipart

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("Formato incompatível")
    end
  end

  describe "DELETE destroy" do
    it "remove template sem vinculos" do
      template = admin.tenant.whatsapp_templates.create!(
        name: "template_removivel",
        language: "pt_BR",
        status: "APPROVED",
        category: "UTILITY",
        body: "Olá",
        template_type: "text",
        header_format: "none"
      )

      delete admin_whatsapp_template_path(template)

      expect(response).to redirect_to(admin_whatsapp_templates_path)
      expect(admin.tenant.whatsapp_templates.where(id: template.id)).not_to exist
    end

    it "bloqueia template usado em notificacoes automaticas" do
      admin.tenant.notification_template_settings.destroy_all
      template = admin.tenant.whatsapp_templates.create!(
        name: "template_notificacao",
        language: "pt_BR",
        status: "APPROVED",
        category: "UTILITY",
        body: "Lead {{1}}",
        template_type: "text",
        header_format: "none"
      )
      admin.tenant.notification_template_settings.create!(
        purpose: "lead_distribution_broker",
        whatsapp_template: template,
        variable_mapping: { "1" => "lead_name" }
      )

      delete admin_whatsapp_template_path(template)

      expect(response).to redirect_to(admin_whatsapp_templates_path)
      expect(admin.tenant.whatsapp_templates.where(id: template.id)).to exist
    end
  end
end

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
      expect(document.css("table th[scope='col']").size).to eq(5)
      expect(response.body).to include("Disparos e campanhas")
      campaign_action = document.at_css("a.ax-btn--primary[href*='new_campaign']")
      expect(campaign_action).to be_present
      expect(campaign_action["style"]).to be_nil
    end

    it "mostra contagem por status em abas e a proxima acao certa para cada situacao" do
      sender = create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: "waba-abas")
      base = { language: "pt_BR", category: "MARKETING", waba_id: sender.waba_id, body: "Olá {{1}}!" }
      admin.tenant.whatsapp_templates.create!(base.merge(name: "aprovado_flow", status: "APPROVED", usage_context: "response_flow", buttons: [{ "kind" => "quick_reply", "text" => "Oi" }]))
      admin.tenant.whatsapp_templates.create!(base.merge(name: "em_analise", status: "PENDING", meta_id: "meta-1", usage_context: "broadcast"))
      admin.tenant.whatsapp_templates.create!(base.merge(name: "recusado", status: "REJECTED", meta_id: "meta-2", usage_context: "broadcast"))

      get admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id)

      document = Nokogiri::HTML(response.body)
      expect(document.css(".wtl-tab").map { |tab| [tab.css("span").last.text, tab.at_css("b").text] }).to eq([["Todos", "3"], ["Aprovados", "1"], ["Em análise", "1"], ["Rejeitados", "1"]])
      expect(document.at_css("a.wtl-tab[href*='status=REJECTED']")).to be_present
      expect(document.text).to include("Criar fluxo").and include("Corrigir").and include("Em análise")
      expect(document.css(".wtl-row").size).to eq(3)

      get admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id, status: "REJECTED")
      expect(Nokogiri::HTML(response.body).css(".wtl-row .wtl-name__link").map(&:text)).to eq(["recusado"])
    end

    it "pede selecao do numero antes de listar templates" do
      create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: "waba-selecao")

      get admin_whatsapp_templates_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Escolha o número / WABA")
      expect(response.body).not_to include("<table")
    end


    it "usa os estados vazios compartilhados para numeros e templates" do
      get admin_whatsapp_templates_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nenhum número ativo cadastrado", "ax-empty-state")

      sender = create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: "waba-vazia")
      get admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nenhum template encontrado", "Sincronize para trazer os modelos desta WABA")
    end

    it "permite gerenciar templates tambem para o numero da integracao principal" do
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
      expect(response.body).to include("55 (47) 3311-1067")
      expect(response.body).to include("55 (47) 2122-8669")
    end
  end

  describe "contexto do numero" do
    it "preserva o numero ao entrar na previa e voltar pelo desktop ou mobile" do
      sender = create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: "waba-previa")
      template = admin.tenant.whatsapp_templates.create!(name: "previa", language: "pt_BR", status: "APPROVED", category: "MARKETING", body: "Olá", waba_id: sender.waba_id)
      listing_path = admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id)
      preview_path = admin_whatsapp_template_path(template, whatsapp_sender_number_id: sender.id)

      get listing_path
      document = Nokogiri::HTML(response.body)
      expect(document.css("a").map { |link| link["href"] }).to include(preview_path)

      get preview_path
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css(".ax-mobile-detail-header a")["href"]).to eq(listing_path)
      expect(document.css("a.ax-contextbar__button").map { |link| link["href"] }).to include(listing_path)
      expect(document.css("a").map { |link| link["href"] }).to include(new_campaign_admin_whatsapp_template_path(template, whatsapp_sender_number_id: sender.id))

      get listing_path
      expect(Nokogiri::HTML(response.body).at_css("a.whatsapp-template-selector__option[aria-current='true']")["href"]).to eq(listing_path)
    end

    it "preserva o numero principal selecionado no formulario e na WABA enviada" do
      integration = WhatsappBusinessIntegration.current(admin.tenant)
      integration.update!(phone_number_id: "principal-test", waba_id: "principal-waba", access_token: "token")
      sender = create(:whatsapp_sender_number, tenant: admin.tenant, phone_number_id: integration.phone_number_id, waba_id: integration.waba_id)
      get admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id)
      expect(response.body).to include(new_admin_whatsapp_template_path(whatsapp_sender_number_id: sender.id))
      get new_admin_whatsapp_template_path(template_type: "text", whatsapp_sender_number_id: sender.id)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('input[name="whatsapp_sender_number_id"]')["value"]).to eq(sender.id.to_s)
      client = instance_double(Whatsapp::CloudClient)
      expect(Whatsapp::CloudClient).to receive(:new).with(sender).and_return(client)
      expect(Whatsapp::TemplateSubmission).to receive(:call) do |template:, client:|
        expect(template.waba_id).to eq(sender.waba_id)
        {ok: true}
      end
      post admin_whatsapp_templates_path, params: {whatsapp_sender_number_id: sender.id, whatsapp_template: {name: "contexto", body: "Olá", language: "pt_BR", category: "MARKETING", template_type: "text"}}
      expect(response).to redirect_to(admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id))
    end

    it "recusa numero inativo ou de outra conta sem usar outro remetente" do
      inactive = create(:whatsapp_sender_number, tenant: admin.tenant, active: false)
      other = Tenant.create!(name: "Outra conta templates", slug: "other-template-sender")
      foreign = create(:whatsapp_sender_number, tenant: other, whatsapp_business_integration: nil)
      [inactive, foreign].each do |sender|
        Current.tenant = admin.tenant
        sign_in admin
        get new_admin_whatsapp_template_path(whatsapp_sender_number_id: sender.id)
        expect(response).to have_http_status(:not_found), "location=#{response.location} flash=#{flash.to_hash}"
      end
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
      document = Nokogiri::HTML(response.body)
      expect(document.css("[data-guided-step]").size).to eq(5)
      expect(document.at_css("aside.ax-guided-aside [data-guided='previewBody']")).to be_present
      expect(document.css("input[type=radio][name='whatsapp_template[category]']").map { |input| input["value"] }).to eq(%w[MARKETING UTILITY AUTHENTICATION])
      expect(document.at_css("input[name='whatsapp_template[header_format]'][value='video']")).to be_present
      # campos do design system: selects com TomSelect e linhas novas clonadas de um <template> do servidor
      expect(document.css("select[name='whatsapp_template[language]']").map { |select| select["data-controller"].to_s }).to all(include("tom-select"))
      expect(document.at_css("template[data-whatsapp-template-form-target='buttonTemplate'] select[name*='__INDEX__']")).to be_present
      expect(document.at_css("template[data-whatsapp-template-form-target='exampleTemplate'] input[id*='__INDEX__']")).to be_present
    end

    it "renderiza editor completo de carousel" do
      get new_admin_whatsapp_template_path(template_type: "carousel")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cards do carrossel")
      expect(response.body).to include("Adicionar card")
      expect(response.body).to include("Mídia do card")
      document = Nokogiri::HTML(response.body)
      expect(document.css("[data-whatsapp-template-form-target=carouselCardList] > .wtb-cardrow").size).to eq(2)
      expect(document.at_css("template[data-whatsapp-template-form-target='carouselCardTemplate'] select[name*='[button_kind]']")["data-controller"]).to include("tom-select")
      expect(response.body).not_to include("Ainda está bloqueado")
    end

    it "renderiza editor completo de flow" do
      get new_admin_whatsapp_template_path(template_type: "flow")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Conexão com Flow")
      expect(response.body).to include("ID do Flow na Meta")
      expect(response.body).to include("Ação do Flow")
      expect(Nokogiri::HTML(response.body).at_css("select[name='whatsapp_template[flow_config][action]']")["data-controller"]).to include("tom-select")
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
      expect(response).to redirect_to(admin_whatsapp_templates_path)
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
      expect(response).to redirect_to(admin_whatsapp_templates_path)
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
      expect(response).to redirect_to(admin_whatsapp_templates_path)
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
      expect(response).to redirect_to(admin_whatsapp_templates_path)
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
    describe "edicao com reenvio para a Meta" do
      let(:sender) { create(:whatsapp_sender_number, tenant: admin.tenant, waba_id: "waba-edit") }
      let(:client) { instance_double(Whatsapp::CloudClient, update_template: { ok: true, data: { "success" => true } }, fetch_template: { ok: true, data: { "status" => "PENDING" } }) }
      let!(:template) do
        admin.tenant.whatsapp_templates.create!(name: "menu_edit", language: "pt_BR", status: "APPROVED", category: "UTILITY", body: "Olá!",
                                                waba_id: sender.waba_id, meta_id: "meta-123", usage_context: "response_flow")
      end

      before { allow(Whatsapp::CloudClient).to receive(:new).and_return(client) }

      def patch_template(attrs) = patch(admin_whatsapp_template_path(template), params: { whatsapp_template: { template_type: "text", header_format: "none" }.merge(attrs) })

      it "reenvia o conteudo alterado para a Meta e guarda o status devolvido" do
        expect(client).to receive(:update_template) do |meta_id, payload|
          expect(meta_id).to eq("meta-123")
          expect(payload[:components].find { |c| c[:type] == "BODY" }[:text]).to eq("Olá, novo texto!")
          expect(payload).not_to include(:name, :language)
          { ok: true, data: { "success" => true } }
        end

        patch_template(body: "Olá, novo texto!", name: "outro_nome")

        expect(response).to redirect_to(admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id))
        expect(template.reload).to have_attributes(body: "Olá, novo texto!", status: "PENDING", name: "menu_edit")
      end

      it "nao reenvia quando so um campo local mudou" do
        expect(client).not_to receive(:update_template)

        patch_template(body: "Olá!", usage_context: "attendance")

        expect(response).to redirect_to(admin_whatsapp_template_path(template))
        expect(template.reload.usage_context).to eq("attendance")
        expect(template.status).to eq("APPROVED")
      end

      it "mostra o erro da Meta e nao grava a alteracao" do
        allow(client).to receive(:update_template).and_return({ ok: false, error: "(#100) Só é possível editar 1 vez a cada 24 horas" })

        patch_template(body: "Texto novo")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("1 vez a cada 24 horas")
        expect(template.reload.body).to eq("Olá!")
      end

      it "bloqueia a edicao enquanto o template esta em analise" do
        template.update_columns(status: "PENDING")
        expect(client).not_to receive(:update_template)

        patch_template(body: "Texto novo")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("não pode ser editado agora")
      end

      it "renderiza todos os botoes existentes na edicao e reenvia sem trunca-los" do
        buttons = (1..8).map { |i| { "kind" => "quick_reply", "text" => "Opção #{i}" } }
        template.update_columns(buttons: buttons)

        get edit_admin_whatsapp_template_path(template)
        expect(Nokogiri::HTML(response.body).css("[data-whatsapp-template-form-target=buttonList] > .whatsapp-template-button-row").size).to eq(8)

        expect(client).to receive(:update_template) do |_meta_id, payload|
          expect(payload[:components].find { |c| c[:type] == "BUTTONS" }[:buttons].size).to eq(8)
          { ok: true, data: { "success" => true } }
        end
        patch_template(body: "Novo corpo", buttons: buttons.each_with_index.to_h { |b, i| [i.to_s, b] })
      end

      it "lista o botao Editar e avisa da nova analise na tela de edicao" do
        get admin_whatsapp_templates_path(whatsapp_sender_number_id: sender.id)
        expect(response.body).to include("Editar e reenviar para aprovação da Meta")

        get edit_admin_whatsapp_template_path(template)
        expect(response.body).to include("nova análise da Meta").and include("Salvar e reenviar para aprovação")
      end
    end

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

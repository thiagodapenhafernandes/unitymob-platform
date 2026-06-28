require "rails_helper"

RSpec.describe "Admin::WhatsappCampaigns", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin, email: "wa-campaign-#{SecureRandom.hex(6)}@salute.test") }
  let(:template) { WhatsappTemplate.create!(name: "lead_nurture", language: "pt_BR", status: "APPROVED", body: "Oi {{1}}, origem {{2}}.") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET index" do
    it "renderiza a camada de selecao por numero" do
      create(:whatsapp_sender_number, display_phone_number: "5511988887777", phone_number_id: "111222333444")

      get admin_whatsapp_campaigns_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Campanhas por número")
      expect(response.body).to include("5511988887777")
      expect(response.body).to include("Abrir campanhas")
    end

    it "filtra campanhas por numero de envio" do
      sender = create(:whatsapp_sender_number, display_phone_number: "5511988887777", phone_number_id: "111222333444")
      other_sender = create(:whatsapp_sender_number, display_phone_number: "5511977776666", phone_number_id: "555666777888")
      WhatsappCampaign.create!(name: "Campanha do numero", whatsapp_template: template, created_by: admin, whatsapp_sender_number: sender)
      WhatsappCampaign.create!(name: "Outra campanha", whatsapp_template: template, created_by: admin, whatsapp_sender_number: other_sender)

      get admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Campanha do numero")
      expect(response.body).not_to include("Outra campanha")
      expect(response.body).to include("Disparos WhatsApp")
      expect(response.body).to include("5511988887777")
      expect(response.body).to include("Nova campanha")
      expect(response.body).to include("Documentação")
      expect(response.body).to include(documentation_admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id))
      expect(response.body).not_to include("Workspace do número")
    end
  end

  describe "GET documentation" do
    it "abre a documentacao operacional como PDF" do
      get documentation_admin_whatsapp_campaigns_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
    end
  end

  describe "GET new" do
    it "renderiza builder em etapas" do
      get new_admin_whatsapp_campaign_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("whatsapp-campaign-builder")
      expect(response.body).to include("Pré-visualizar audiência")
      expect(response.body).to include("Enviar teste")
    end

    it "pre-seleciona template vindo do catalogo" do
      get new_admin_whatsapp_campaign_path(whatsapp_template_id: template.id)

      expect(response).to have_http_status(:ok)
      selected = Nokogiri::HTML(response.body).at_css("select#whatsapp_campaign_whatsapp_template_id option[selected]")
      expect(selected&.[]("value")).to eq(template.id.to_s)
    end
  end

  describe "GET show" do
    it "renderiza detalhe operacional da campanha" do
      sender = create(:whatsapp_sender_number)
      campaign = WhatsappCampaign.create!(
        name: "Campanha monitorada",
        whatsapp_template: template,
        whatsapp_sender_number: sender,
        group_name: "Repescagem",
        created_by: admin,
        total_recipients: 1,
        sent_count: 1,
        delivered_count: 1,
        read_count: 1,
        replied_count: 1
      )
      lead = create(:lead, admin_user: admin, phone: "(11) 99999-0000")
      campaign.campaign_messages.create!(lead: lead, phone_number: "5511999990000", status: "replied")

      get admin_whatsapp_campaign_path(campaign)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Campanha monitorada")
      expect(response.body).to include("Performance")
      expect(response.body).to include("Mensagens recentes")
    end
  end

  describe "GET status" do
    it "retorna payload para atualizar progresso em tempo real" do
      campaign = WhatsappCampaign.create!(
        name: "Campanha live",
        whatsapp_template: template,
        created_by: admin,
        status: "processing"
      )
      sent_lead = create(:lead, admin_user: admin, name: "Lead enviado", phone: "(11) 99999-0000")
      failed_lead = create(:lead, admin_user: admin, name: "Lead falhou", phone: "(11) 99999-0001")
      pending_lead = create(:lead, admin_user: admin, name: "Lead pendente", phone: "(11) 99999-0002")
      campaign.campaign_messages.create!(lead: sent_lead, phone_number: "5511999990000", status: "sent")
      campaign.campaign_messages.create!(lead: failed_lead, phone_number: "5511999990001", status: "failed", failure_reason: "Contato inválido")
      campaign.campaign_messages.create!(lead: pending_lead, phone_number: "5511999990002", status: "pending")

      get status_admin_whatsapp_campaign_path(campaign), headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["status"]).to eq("processing")
      expect(data["active"]).to eq(true)
      expect(data["progress_percent"]).to eq(66.7)
      expect(data["pending_count"]).to eq(1)
      expect(data["metrics"]).to include("total" => 3, "sent" => 1, "failed" => 1)
      expect(data["recent_messages"].map { |message| message["recipient_name"] }).to include("Lead enviado", "Lead falhou", "Lead pendente")
    end

    it "inclui cards dinamicos de respostas por botao" do
      button_template = WhatsappTemplate.create!(
        name: "campanha_live_botoes",
        language: "pt_BR",
        status: "APPROVED",
        body: "Escolha.",
        buttons: { "0" => { "kind" => "quick_reply", "text" => "Saiba mais" } }
      )
      campaign = WhatsappCampaign.create!(
        name: "Campanha live botões",
        whatsapp_template: button_template,
        created_by: admin,
        status: "processing",
        response_decisions: {
          buttons: [
            {
              key: button_template.interactive_buttons.first["key"],
              text: "Saiba mais",
              kind: "quick_reply",
              action: "ignore"
            }
          ]
        }
      )
      campaign.campaign_messages.create!(phone_number: "5511999990000", status: "replied", reply_button_text: "Saiba mais")

      get status_admin_whatsapp_campaign_path(campaign), headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["response_cards"].first).to include("label" => "Saiba mais", "count" => 1)
    end
  end

  describe "POST preview_audience" do
    it "retorna contagem da audiencia" do
      create(:lead, name: "Lead Preview", phone: "(47) 99999-0000", origin: "site", status: "Novo", admin_user: admin)

      post preview_audience_admin_whatsapp_campaigns_path,
           params: {
             whatsapp_campaign: {
               audience_mode: "filters",
               audience_definition: {
                 conditions: {
                   "0" => { field: "status", operator: "equals", value: "Novo" },
                   "1" => { field: "origin", operator: "equals", value: "site" },
                   "2" => { field: "admin_user_id", operator: "equals", value: admin.id }
                 }
               }
             }
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["valid_phone_count"]).to eq(1)
      expect(data["sample"].first["name"]).to eq("Lead Preview")
    end

    it "retorna preview de importacao CSV" do
      file = Tempfile.new(["leads", ".csv"])
      file.write("nome,telefone,email,origem,status\nMaria Silva,11999990000,maria@example.com,importacao,Novo\n")
      file.rewind

      post preview_audience_admin_whatsapp_campaigns_path,
           params: {
             whatsapp_campaign: {
               audience_mode: "spreadsheet",
               audience_file: Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "leads.csv")
             }
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["ok"]).to eq(true)
      expect(data["valid_phone_count"]).to eq(1)
      expect(data["sample"].first["name"]).to eq("Maria Silva")
    ensure
      file&.close!
    end
  end

  describe "POST preview_template" do
    it "renderiza corpo do template" do
      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: template.id, template_variables: { "1" => "{{nome}}", "2" => "{{origem}}" } } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["body"]).to eq("Oi Maria Lead, origem site.")
    end

    it "retorna botoes do template para configurar decisoes comerciais" do
      button_template = WhatsappTemplate.create!(
        name: "campanha_com_ctas",
        language: "pt_BR",
        status: "APPROVED",
        body: "Escolha uma opção.",
        buttons: {
          "0" => { "kind" => "quick_reply", "text" => "Saiba mais" },
          "1" => { "kind" => "quick_reply", "text" => "Descadastrar" }
        }
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: button_template.id } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["buttons"].map { |button| button["text"] }).to eq(["Saiba mais", "Descadastrar"])
      expect(data["buttons"].map { |button| button["action"] }).to eq(["generate_lead", "unsubscribe"])
    end

    it "retorna schema dinamico para todas as variaveis do template" do
      rich_template = WhatsappTemplate.create!(
        name: "lead_copy_superintendents",
        language: "pt_BR",
        status: "APPROVED",
        body: <<~BODY
          Fonte: {{1}}
          Nome do lead: {{2}}
          Telefone: {{3}}
          Email: {{4}}
          Infos: {{5}}
          Obs: {{6}}
          Converteu em: {{7}}

          Agente responsável: {{8}}
          Contato do agente: {{9}}
        BODY
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: rich_template.id } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["variable_count"]).to eq(9)
      expect(data["variables_schema"].map { |item| item["placeholder"] }).to eq((1..9).map { |index| "{{#{index}}}" })
      expect(data["variables_schema"].find { |item| item["index"] == 1 }["selected"]).to eq("{{origem}}")
      expect(data["variables_schema"].find { |item| item["index"] == 8 }["selected"]).to eq("{{corretor}}")
      expect(data["variables_schema"].find { |item| item["index"] == 9 }["selected"]).to eq("{{corretor_telefone}}")
    end

    it "isola contexto quando varias variaveis aparecem na mesma linha" do
      multi_template = WhatsappTemplate.create!(
        name: "reengajamento_simples_u1",
        language: "pt_BR",
        status: "APPROVED",
        body: "Olá {{1}}! Aqui é {{2}} da {{3}}. Posso te ajudar no seu atendimento?"
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: multi_template.id } },
           headers: { "ACCEPT" => "application/json" }

      data = JSON.parse(response.body)
      expect(data["variables_schema"].map { |item| item["context"] }).to eq([
        "Olá {{1}}!",
        "Aqui é {{2}} da",
        "da {{3}}."
      ])
      expect(data["variables_schema"].map { |item| item["selected"] }).to eq([
        "{{nome}}",
        "{{corretor}}",
        "{{empresa}}"
      ])
    end

    it "retorna variaveis de cabecalho e URL dinamica do template aprovado" do
      component_template = WhatsappTemplate.create!(
        name: "template_com_preambulos",
        language: "pt_BR",
        status: "APPROVED",
        template_type: "text",
        header_format: "text",
        header_text: "Oferta para {{1}}",
        body: "Olá {{2}}, veja as condições.",
        buttons: { "0" => { "kind" => "url", "text" => "Abrir", "url" => "https://example.com/{{3}}" } },
        components: [
          { "type" => "HEADER", "format" => "TEXT", "text" => "Oferta para {{1}}" },
          { "type" => "BODY", "text" => "Olá {{2}}, veja as condições." },
          { "type" => "BUTTONS", "buttons" => [{ "type" => "URL", "text" => "Abrir", "url" => "https://example.com/{{3}}" }] }
        ]
      )

      post preview_template_admin_whatsapp_campaigns_path,
           params: { whatsapp_campaign: { whatsapp_template_id: component_template.id } },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["variable_count"]).to eq(3)
      expect(data["variables_schema"].map { |item| item["placeholder"] }).to eq(["{{1}}", "{{2}}", "{{3}}"])
      expect(data["variables_schema"].map { |item| item["context"] }).to include(
        "Cabeçalho: Oferta para {{1}}",
        "Olá {{2}}, veja as condições.",
        "Botão 1 · URL: https://example.com/{{3}}"
      )
    end

    it "aceita PATCH quando o formulario de edicao envia _method no FormData" do
      patch preview_template_admin_whatsapp_campaigns_path,
            params: { whatsapp_campaign: { whatsapp_template_id: template.id, template_variables: { "1" => "{{nome}}", "2" => "{{origem}}" } } },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["body"]).to eq("Oi Maria Lead, origem site.")
    end
  end

  describe "POST send_test" do
    it "envia teste com componente de cabecalho de imagem quando o template exige midia" do
      sender = create(:whatsapp_sender_number)
      media_template = WhatsappTemplate.create!(
        name: "campanha_fake",
        language: "pt_BR",
        status: "APPROVED",
        template_type: "text",
        header_format: "image",
        header_media_handle: "https://cdn.example.test/header.png",
        body: "Escolha uma das opções abaixo.",
        components: [
          {
            "type" => "HEADER",
            "format" => "IMAGE",
            "example" => { "header_handle" => ["https://cdn.example.test/header.png"] }
          },
          { "type" => "BODY", "text" => "Escolha uma das opções abaixo." }
        ]
      )
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).with(sender).and_return(client)
      allow(client).to receive(:send_template).and_return({ ok: true, message_id: "wamid.media" })

      post send_test_admin_whatsapp_campaigns_path,
           params: {
             test_phone: "5521990872427",
             whatsapp_campaign: {
               whatsapp_sender_number_id: sender.id,
               whatsapp_template_id: media_template.id
             }
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data).to include("ok" => true, "message_id" => "wamid.media", "delivery_status" => "sent")
      expect(data["delivery_hint"]).to include("webhook de status")
      expect(client).to have_received(:send_template).with(
        hash_including(
          name: "campanha_fake",
          components: [
            {
              type: "header",
              parameters: [
                { type: "image", image: { link: "https://cdn.example.test/header.png" } }
              ]
            }
          ]
        )
      )
    end

    it "retorna detalhes acionaveis quando a Meta rejeita o formato do template" do
      sender = create(:whatsapp_sender_number)
      client = instance_double(Whatsapp::CloudClient)
      allow(Whatsapp::CloudClient).to receive(:new).with(sender).and_return(client)
      allow(client).to receive(:send_template).and_return(
        {
          ok: false,
          error: "(#132012) Parameter format does not match format in the created template.",
          meta_error: { code: 132012, type: "OAuthException", trace_id: "TRACE123" }
        }
      )

      post send_test_admin_whatsapp_campaigns_path,
           params: {
             test_phone: "5521990872427",
             whatsapp_campaign: {
               whatsapp_sender_number_id: sender.id,
               whatsapp_template_id: template.id,
               template_variables: { "1" => "{{nome}}", "2" => "{{origem}}" }
             }
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      data = JSON.parse(response.body)
      expect(data["error"]).to include("#132012")
      expect(data["error_hint"]).to include("formato enviado não corresponde ao template aprovado")
      expect(data["meta_error"]).to include(
        "code" => 132012,
        "type" => "OAuthException",
        "trace_id" => "TRACE123"
      )
    end
  end

  describe "POST create" do
    it "salva rascunho" do
      sender = create(:whatsapp_sender_number)

      expect {
        post admin_whatsapp_campaigns_path, params: {
          commit_action: "draft",
          whatsapp_campaign: {
            name: "Rascunho",
            whatsapp_template_id: template.id,
            whatsapp_sender_number_id: sender.id,
            group_name: "Captação Alto Padrão",
            send_rate: 30,
            audience_filters: { status: "Novo" },
            template_variables: { "1" => "{{nome}}" }
          }
        }
      }.to change(WhatsappCampaign, :count).by(1)

      expect(WhatsappCampaign.last.status).to eq("draft")
      expect(WhatsappCampaign.last.whatsapp_sender_number).to eq(sender)
      expect(WhatsappCampaign.last.group_name).to eq("Captação Alto Padrão")
    end

    it "agenda disparo futuro" do
      future = 2.hours.from_now.change(usec: 0)

      expect {
        post admin_whatsapp_campaigns_path, params: {
          commit_action: "schedule",
          whatsapp_campaign: {
            name: "Agendada",
            whatsapp_template_id: template.id,
            send_rate: 30,
            scheduled_at: future,
            audience_filters: { status: "Novo" },
            template_variables: { "1" => "{{nome}}" }
          }
        }
      }.to have_enqueued_job(Whatsapp::CampaignStartJob)

      expect(WhatsappCampaign.last.status).to eq("scheduled")
    end
  end

  describe "POST whatsapp sender numbers" do
    it "adiciona numero de envio" do
      expect {
        post admin_whatsapp_sender_numbers_path, params: {
          whatsapp_sender_number: {
            label: "Relacionamento",
            display_phone_number: "5511966665555",
            phone_number_id: "999888777666",
            waba_id: "616242481017427"
          }
        }
      }.to change(WhatsappSenderNumber, :count).by(1)

      expect(response).to redirect_to(admin_whatsapp_campaigns_path(whatsapp_sender_number_id: WhatsappSenderNumber.last.id))
      expect(WhatsappSenderNumber.last.label).to eq("Relacionamento")
    end

    it "atualiza parametros de CPL do numero" do
      sender = create(:whatsapp_sender_number)

      patch admin_whatsapp_sender_number_path(sender), params: {
        whatsapp_sender_number: {
          cpl_sent_unit_price: "0,75",
          cpl_fla_unit_price: "0,20"
        }
      }

      expect(response).to redirect_to(admin_whatsapp_campaigns_path(whatsapp_sender_number_id: sender.id))
      expect(sender.reload.cpl_sent_unit_price).to eq(0.75.to_d)
      expect(sender.cpl_fla_unit_price).to eq(0.20.to_d)
    end
  end

  describe "operacoes da campanha" do
    let(:campaign) { WhatsappCampaign.create!(name: "Operação", whatsapp_template: template, created_by: admin, status: "processing") }
    let(:lead) { create(:lead, admin_user: admin, phone: "(47) 99999-0000") }

    it "cancela pendentes" do
      campaign.campaign_messages.create!(lead: lead, phone_number: "5547999990000", status: "pending")

      post cancel_pending_admin_whatsapp_campaign_path(campaign)

      expect(response).to redirect_to(admin_whatsapp_campaign_path(campaign))
      expect(campaign.campaign_messages.last.reload.status).to eq("cancelled")
    end

    it "reprocessa falhas" do
      campaign.campaign_messages.create!(lead: lead, phone_number: "5547999990000", status: "failed", failure_reason: "HTTP 500")

      expect {
        post retry_failed_admin_whatsapp_campaign_path(campaign)
      }.to have_enqueued_job(Whatsapp::BulkSendJob)

      expect(campaign.campaign_messages.last.reload.status).to eq("pending")
    end
  end
end

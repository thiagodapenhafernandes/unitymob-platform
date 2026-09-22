require "rails_helper"

RSpec.describe "Admin::AutomationWorkflows", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "workflow-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  def publishable_definition
    {
      "schema_version" => 1,
      "nodes" => [
        {
          "id" => "entry_1",
          "type" => "entry",
          "label" => "Quando observar",
          "config" => { "trigger" => "lead_created", "entry_policy" => "future" }
        },
        {
          "id" => "action_1",
          "type" => "action",
          "label" => "Registrar nota",
          "config" => { "action_type" => "add_note", "body" => "via workflow" }
        }
      ],
      "edges" => [{ "from" => "entry_1", "to" => "action_1" }],
      "viewport" => { "x" => 0, "y" => 0, "zoom" => 1 }
    }
  end

  describe "GET index" do
    it "redireciona para o hub de automacao em vez de quebrar sem template" do
      get admin_automation_workflows_path

      expect(response).to redirect_to(admin_automation_rules_path)
    end
  end

  describe "POST create" do
    it "cria fluxo com versao rascunho e redireciona para o builder" do
      expect {
        post admin_automation_workflows_path, params: {
          automation_workflow: { name: "Resgate de lead frio" }
        }
      }.to change(AutomationWorkflow, :count).by(1)
        .and change(AutomationWorkflowVersion, :count).by(1)

      workflow = AutomationWorkflow.last
      expect(workflow.name).to eq("Resgate de lead frio")
      expect(workflow.draft_version).to be_present
      expect(response).to redirect_to(builder_admin_automation_workflow_path(workflow))
    end
  end

  describe "GET builder" do
    it "renderiza o builder com o JSON versionado" do
      workflow = AutomationWorkflow.create!(name: "Nutrir lead")
      workflow.draft_version!

      get builder_admin_automation_workflow_path(workflow)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("automation-workflow-builder")
      expect(response.body).to include("Quando observar")
      expect(response.body).to include("Salvar e Ativar")
      expect(response.body).to include("Sair para listagem")
      expect(response.body).to include(admin_automation_workflows_path)
      expect(response.body).to include("Histórico do acompanhamento")
      expect(response.body).to include("Pendências antes de ativar")
      expect(response.body).to include("Automação horizontal")
      expect(response.body).not_to include("assign_agent")
    end

    it "renderiza execucoes recentes do workflow" do
      lead = create(:lead, admin_user: admin, status: "Em Atendimento")
      workflow = AutomationWorkflow.create!(name: "Nutrir lead")
      version = workflow.draft_version!
      version.update!(definition: publishable_definition)
      workflow.publish!(version: version, admin_user: admin)
      execution = AutomationExecution.create!(
        automation_workflow: workflow,
        automation_workflow_version: workflow.active_version,
        lead: lead,
        status: "completed"
      )
      execution.steps.create!(node_id: "action_1", node_type: "action", status: "completed")

      get builder_admin_automation_workflow_path(workflow)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(lead.display_name)
      expect(response.body).to include("Concluida")
    end
  end

  describe "PATCH save_draft" do
    it "salva nome e definicao do rascunho" do
      workflow = AutomationWorkflow.create!(name: "Antigo")
      workflow.draft_version!
      definition = Automation::WorkflowDefinition.default_definition.deep_dup
      definition["nodes"] << {
        "id" => "wait_1",
        "type" => "wait",
        "label" => "Esperar retorno",
        "config" => { "amount" => "2", "unit" => "days" }
      }
      definition["edges"] = [
        { "from" => "entry_1", "to" => "wait_1" }
      ]

      patch save_draft_admin_automation_workflow_path(workflow), params: {
        automation_workflow: {
          name: "Novo nome",
          definition_json: definition.to_json
        }
      }

      expect(response).to redirect_to(builder_admin_automation_workflow_path(workflow))
      expect(workflow.reload.name).to eq("Novo nome")
      expect(workflow.draft_version.definition_hash[:nodes].size).to eq(2)
    end

    it "marca workflow de campanha como personalizado quando salvo pelo builder" do
      sender = create(:whatsapp_sender_number)
      template = WhatsappTemplate.create!(
        name: "campanha_builder_personalizado",
        language: "pt_BR",
        status: "APPROVED",
        body: "Escolha.",
        buttons: { "0" => { "kind" => "quick_reply", "text" => "Saiba mais" } }
      )
      button = template.interactive_buttons.first
      campaign = WhatsappCampaign.create!(
        name: "Campanha com builder",
        whatsapp_template: template,
        whatsapp_sender_number: sender,
        created_by: admin,
        response_decisions: {
          buttons: [
            {
              key: button["key"],
              text: "Saiba mais",
              kind: "quick_reply",
              action: "send_message",
              message: "Retorno recebido."
            }
          ]
        }
      )
      workflow = Automation::WhatsappCampaignWorkflowSync.call(campaign)
      definition = workflow.active_version.definition_hash.deep_dup
      definition[:nodes] << {
        "id" => "manual_note",
        "type" => "action",
        "label" => "Ajuste fino",
        "config" => { "action_type" => "add_note", "body" => "feito no builder" }
      }

      patch save_draft_admin_automation_workflow_path(workflow), params: {
        automation_workflow: {
          name: workflow.name,
          definition_json: definition.to_json
        }
      }

      source = workflow.reload.draft_version.definition_hash[:source]
      expect(response).to redirect_to(builder_admin_automation_workflow_path(workflow))
      expect(source[:managed_by_campaign]).to eq(false)
      expect(source[:customized_by_advanced_user]).to eq(true)
      expect(source[:customized_by_admin_user_id]).to eq(admin.id)
      expect(source[:sync_mode]).to eq("advanced_custom")
      expect(workflow).to be_whatsapp_campaign_customized
    end
  end

  describe "PATCH publish" do
    it "publica a versao do fluxo" do
      workflow = AutomationWorkflow.create!(name: "Ativar")
      version = workflow.draft_version!

      patch publish_admin_automation_workflow_path(workflow), params: {
        automation_workflow: {
          name: "Ativar",
          definition_json: publishable_definition.to_json
        }
      }

      expect(response).to redirect_to(builder_admin_automation_workflow_path(workflow))
      expect(workflow.reload.status).to eq("active")
      expect(workflow.active_version).to be_present
    end

    it "mantem a definicao publicada ao voltar para o builder" do
      workflow = AutomationWorkflow.create!(name: "Ativar")
      workflow.draft_version!

      patch publish_admin_automation_workflow_path(workflow), params: {
        automation_workflow: {
          name: "Ativar",
          definition_json: publishable_definition.to_json
        }
      }

      expect(response).to redirect_to(builder_admin_automation_workflow_path(workflow))

      get builder_admin_automation_workflow_path(workflow)

      draft = workflow.reload.draft_version
      expect(draft).to be_present
      expect(draft.definition_hash[:nodes].size).to eq(2)
      expect(draft.definition_hash[:nodes].last[:label]).to eq("Registrar nota")
      expect(draft.definition_hash[:edges]).to eq([{ "from" => "entry_1", "to" => "action_1" }])
      expect(response.body).to include("Registrar nota")
    end

    it "bloqueia publicacao de fluxo incompleto" do
      workflow = AutomationWorkflow.create!(name: "Incompleto")
      version = workflow.draft_version!

      patch publish_admin_automation_workflow_path(workflow), params: {
        automation_workflow: {
          name: "Incompleto",
          definition_json: version.definition.to_json
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(workflow.reload.status).to eq("draft")
      expect(response.body).to include("precisa ter ao menos uma etapa apos a entrada")
    end

    it "bloqueia ação vertical de distribuição no builder" do
      workflow = AutomationWorkflow.create!(name: "Vertical")
      workflow.draft_version!
      definition = publishable_definition.deep_dup
      definition["nodes"].last["config"] = { "action_type" => "assign_agent", "admin_user_id" => admin.id }

      patch publish_admin_automation_workflow_path(workflow), params: {
        automation_workflow: {
          name: "Vertical",
          definition_json: definition.to_json
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(workflow.reload.status).to eq("draft")
      expect(response.body).to include("acao vertical de distribuicao")
    end

    it "bloqueia mover para etapa controlada pela distribuição" do
      workflow = AutomationWorkflow.create!(name: "Represar")
      workflow.draft_version!
      definition = publishable_definition.deep_dup
      definition["nodes"].last["config"] = { "action_type" => "move_stage", "to" => "Represado" }

      patch publish_admin_automation_workflow_path(workflow), params: {
        automation_workflow: {
          name: "Represar",
          definition_json: definition.to_json
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Distribuicao de Leads")
    end
  end

  describe "POST simulate" do
    it "renderiza simulação sem publicar o fluxo" do
      lead = create(:lead, status: "Em Atendimento", admin_user: admin)
      workflow = AutomationWorkflow.create!(name: "Simular")
      workflow.draft_version!
      definition = publishable_definition.deep_dup
      definition["nodes"].first["config"] = { "trigger" => "lead_stage_changed", "entry_policy" => "existing_and_future" }
      definition["nodes"].insert(1, {
        "id" => "condition_1",
        "type" => "condition",
        "label" => "Em atendimento",
        "config" => { "stage" => "Em Atendimento" }
      })
      definition["edges"] = [
        { "from" => "entry_1", "to" => "condition_1" },
        { "from" => "condition_1", "to" => "action_1" }
      ]

      patch simulate_admin_automation_workflow_path(workflow), params: {
        automation_workflow: {
          name: "Simular",
          definition_json: definition.to_json
        }
      }

      expect(response).to redirect_to(builder_admin_automation_workflow_path(workflow))
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Simulação do builder")
      expect(response.body).to include(lead.display_name)
      expect(workflow.reload.status).to eq("draft")
    end
  end

  describe "conversa por WhatsApp" do
    let(:template) do
      admin.tenant.whatsapp_templates.create!(
        name: "menu_conversa", language: "pt_BR", status: "APPROVED", usage_context: "response_flow", waba_id: "waba-conv", category: "UTILITY", body: "Olá!",
        buttons: [{ "kind" => "quick_reply", "text" => "Comprar" }, { "kind" => "quick_reply", "text" => "Alugar" }, { "kind" => "url", "text" => "Site", "url" => "https://x.test" }]
      )
    end

    it "cria só pelo nome: a tela não pede template nem número" do
      template

      get admin_new_automation_workflow_entry_path

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css("input[name='automation_workflow[name]']")).to be_present
      expect(html.at_css("select")).to be_nil
      expect(html.at_css("input[name='whatsapp_template_id']")).to be_nil
    end

    it "vindo de um fluxo de resposta mantém o template escolhido como ponto de partida" do
      get admin_new_automation_workflow_entry_path(whatsapp_template_id: template.id)

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("input[type='hidden'][name='whatsapp_template_id']")["value"]).to eq(template.id.to_s)
    end

    it "cria em branco e leva ao builder, onde o início é escolhido" do
      post admin_automation_workflows_path, params: { automation_workflow: { name: "Só o nome" } }

      workflow = admin.tenant.automation_workflows.order(:id).last
      expect(response).to redirect_to(builder_admin_automation_workflow_path(workflow))
      expect(workflow.draft_version.definition_hash[:nodes].map { |node| node[:type] }).to eq(["entry"])
    end

    it "entrega ao builder os números ativos e os templates com o caminho por botão, para filtrar por número" do
      template
      sender = admin.tenant.whatsapp_sender_numbers.create!(label: "Comercial", display_phone_number: "+5511999990000", phone_number_id: "pn-conv", waba_id: "waba-conv")
      workflow = admin.tenant.automation_workflows.create!(name: "Construtor")
      workflow.versions.create!(version_number: 1, status: "draft", definition: Automation::WorkflowDefinition.default_definition)

      get builder_admin_automation_workflow_path(workflow)

      catalog = JSON.parse(Nokogiri::HTML(response.body).at_css("script[data-automation-workflow-builder-target='catalog']").text)
      expect(catalog["whatsapp_senders"]).to include(a_hash_including("id" => sender.id, "waba_id" => "waba-conv"))
      entry = catalog["whatsapp_flow_templates"].find { |item| item["id"] == template.id }
      expect(entry).to include("waba_id" => "waba-conv")
      expect(entry["scaffold"]["nodes"].map { |node| node["type"] }.tally).to include("response_condition" => 2)
    end

    it "monta um caminho por botao de resposta e o rascunho ja pode ser publicado" do
      post admin_automation_workflows_path, params: { whatsapp_template_id: template.id, automation_workflow: { name: "Conversa menu" } }

      workflow = admin.tenant.automation_workflows.order(:id).last
      definition = workflow.draft_version.definition_hash
      expect(definition[:nodes].map { |node| node[:type] }.tally).to include("entry" => 1, "response_condition" => 2, "action" => 2)
      expect(definition[:nodes].first.dig(:config, :trigger)).to eq("whatsapp_flow_button")
      expect(Automation::WorkflowDefinition.validate(definition, mode: :publish)).to be_empty
    end

    it "ao publicar com receptivo ligado, o número passa a responder por esta automação" do
      sender = admin.tenant.whatsapp_sender_numbers.create!(label: "Comercial", display_phone_number: "+5511999990000", phone_number_id: "pn-rec", waba_id: "waba-conv")
      post admin_automation_workflows_path, params: { whatsapp_template_id: template.id, automation_workflow: { name: "Receptivo" } }
      workflow = admin.tenant.automation_workflows.order(:id).last
      definition = workflow.draft_version.definition_hash
      definition[:nodes].first[:config].merge!(whatsapp_sender_number_id: sender.id.to_s, use_as_receptive: true)

      patch publish_admin_automation_workflow_path(workflow), params: { automation_workflow: { name: "Receptivo", definition_json: definition.to_json } }

      expect(response).to redirect_to(builder_admin_automation_workflow_path(workflow))
      expect(workflow.reload.status).to eq("active")
      expect(sender.reload.receptive_response_flow&.automation_workflow_id).to eq(workflow.id)
    end

    it "publicar com conflito de fluxo de resposta não ativa nada e explica" do
      other = admin.tenant.automation_workflows.create!(name: "Outra")
      admin.tenant.whatsapp_response_flows.create!(name: "Menu do time", whatsapp_template: template, automation_workflow: other)
      sender = admin.tenant.whatsapp_sender_numbers.create!(label: "Comercial", display_phone_number: "+5511999990000", phone_number_id: "pn-conf", waba_id: "waba-conv")
      post admin_automation_workflows_path, params: { whatsapp_template_id: template.id, automation_workflow: { name: "Receptivo" } }
      workflow = admin.tenant.automation_workflows.order(:id).last
      definition = workflow.draft_version.definition_hash
      definition[:nodes].first[:config].merge!(whatsapp_sender_number_id: sender.id.to_s, use_as_receptive: true)

      patch publish_admin_automation_workflow_path(workflow), params: { automation_workflow: { name: "Receptivo", definition_json: definition.to_json } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Menu do time")
      expect(workflow.reload.status).not_to eq("active")
    end

    it "oferece as etapas de conversa no construtor" do
      workflow = admin.tenant.automation_workflows.create!(name: "Construtor")
      workflow.versions.create!(version_number: 1, status: "draft", definition: Automation::WorkflowDefinition.default_definition)

      get builder_admin_automation_workflow_path(workflow)

      catalog = JSON.parse(Nokogiri::HTML(response.body).at_css("script[data-automation-workflow-builder-target='catalog']").text)
      expect(catalog["actions"]).to include("send_whatsapp_buttons" => "Perguntar com botões", "send_whatsapp_list" => "Perguntar com lista", "transfer_to_attendant" => "Passar para atendente")
      expect(catalog["triggers"]).to include("whatsapp_flow_button")
    end

    it "valida os limites do WhatsApp nas perguntas" do
      definition = ->(type, options, message = "Pergunta") do
        { "nodes" => [{ "id" => "entry_1", "type" => "entry", "config" => { "trigger" => "whatsapp_flow_button" } },
                      { "id" => "ask", "type" => "action", "config" => { "action_type" => type, "message" => message, "options" => options } },
                      { "id" => "wait", "type" => "await_whatsapp_response", "config" => { "timeout_amount" => "1", "timeout_unit" => "hours" } },
                      { "id" => "end", "type" => "action", "config" => { "action_type" => "add_note", "body" => "x" } }],
          "edges" => [{ "from" => "entry_1", "to" => "ask" }, { "from" => "ask", "to" => "wait" }, { "from" => "wait", "to" => "end" }] }
      end

      expect(Automation::WorkflowDefinition.validate(definition.call("send_whatsapp_buttons", "A\nB"), mode: :publish)).to be_empty
      expect(Automation::WorkflowDefinition.validate(definition.call("send_whatsapp_buttons", "A\nB\nC\nD"), mode: :publish).join).to include("mais de 3 opcoes")
      expect(Automation::WorkflowDefinition.validate(definition.call("send_whatsapp_buttons", "Uma opção com mais de vinte letras"), mode: :publish).join).to include("acima de 20 caracteres")
      expect(Automation::WorkflowDefinition.validate(definition.call("send_whatsapp_list", ""), mode: :publish).join).to include("sem opcoes")
    end
  end
end

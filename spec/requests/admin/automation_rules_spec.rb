require "rails_helper"

RSpec.describe "Admin::AutomationRules", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "autom-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  describe "GET index" do
    it "lista as regras no formato Quando -> Então" do
      AutomationRule.create!(name: "Resgate de lead frio", trigger_event: "lead_idle",
                             conditions: { "idle_hours" => 48 }, actions: [{ "type" => "add_note", "body" => "x" }])

      get admin_automation_rules_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Automação")
      expect(response.body).to include("Resgate de lead frio")
      expect(response.body).to include("QUANDO")
      expect(response.body).to include("INTERVENÇÃO", "ax-dismissible-hint", 'data-dismissible-key-value="automacao"')
    end
  end

  describe "GET new" do
    it "renderiza a entrada do novo builder de fluxo" do
      get new_admin_automation_rule_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nome da intervenção")
    end
  end

  describe "GET edit" do
    it "renderiza o formulário da regra com o contrato do builder" do
      rule = AutomationRule.create!(
        name: "Acompanhamento editável",
        trigger_event: "lead_idle",
        conditions: { "idle_hours" => 48 },
        actions: [{ "type" => "add_note", "body" => "Retomar contato" }]
      )

      get edit_admin_automation_rule_path(rule)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Editar intervenção de automação", "Identificação e gatilho", "Intervenções")
      expect(response.body).to include('data-controller="automation-builder"', 'data-automation-builder-target="rows"', 'data-automation-builder-target="template"')
      expect(response.body).to include("Acompanhamento editável", "Retomar contato")
    end
  end

  describe "POST create" do
    it "cria regra parseando actions_json e condições" do
      expect {
        post admin_automation_rules_path, params: {
          automation_rule: {
            name: "Nova regra",
            trigger_event: "lead_created",
            conditions: { stage: "Novo", source: "" },
            actions_json: [{ type: "create_task", title: "Tarefa auto" }].to_json
          }
        }
      }.to change(AutomationRule, :count).by(1)

      rule = AutomationRule.last
      expect(rule.action_list.first["type"]).to eq("create_task")
      expect(rule.action_list.first["title"]).to eq("Tarefa auto")
      expect(rule.conditions_hash[:stage]).to eq("Novo")
      expect(rule.conditions_hash[:source]).to be_nil
    end

    it "ignora ações verticais de distribuição nas regras novas" do
      post admin_automation_rules_path, params: {
        automation_rule: {
          name: "Nao redistribuir",
          trigger_event: "lead_idle",
          conditions: { idle_hours: 2 },
          actions_json: [{ type: "assign_agent", admin_user_id: admin.id }].to_json
        }
      }

      rule = AutomationRule.last
      expect(rule.name).to eq("Nao redistribuir")
      expect(rule.action_list).to eq([])
    end

    it "ignora mover etapa para estado controlado pela distribuição" do
      post admin_automation_rules_path, params: {
        automation_rule: {
          name: "Nao represar",
          trigger_event: "lead_idle",
          conditions: { idle_hours: 2 },
          actions_json: [{ type: "move_stage", to: "Represado" }].to_json
        }
      }

      rule = AutomationRule.last
      expect(rule.name).to eq("Nao represar")
      expect(rule.action_list).to eq([])
    end
  end

  describe "POST simulate" do
    it "simula a regra sem salvar" do
      create(:lead, name: "Lead Simulado", status: "Em Atendimento")

      expect {
        post simulate_admin_automation_rules_path, params: {
          automation_rule: {
            name: "Simular",
            trigger_event: "lead_stage_changed",
            conditions: { stage: "Em Atendimento" },
            actions_json: [{ type: "add_note", body: "teste" }].to_json
          }
        }
      }.not_to change(AutomationRule, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Simulação da regra")
      expect(response.body).to include("Lead Simulado")
    end
  end

  describe "PATCH toggle_active" do
    it "pausa e reativa a regra" do
      rule = AutomationRule.create!(name: "x", trigger_event: "lead_created", active: true)
      patch toggle_active_admin_automation_rule_path(rule)
      expect(rule.reload.active).to be false
    end
  end

  describe "POST create_example" do
    it "cria a regra de exemplo" do
      expect { post create_example_admin_automation_rules_path }.to change(AutomationRule, :count).by(1)
      expect(AutomationRule.last.name).to eq("Resgate de lead frio")
    end
  end

  describe "POST test_webhook" do
    it "executa uma entrega de teste e retorna o status" do
      delivery = AutomationWebhookDelivery.new(status: "success", response_code: 200)
      allow(Automation::WebhookTestDelivery).to receive(:call).and_return(delivery)

      post test_webhook_admin_automation_rules_path,
           params: {
             url: "https://example.test/hook",
             http_method: "post",
             headers: "X-Test: 1",
             payload_template: { lead: { name: "{{nome}}" } }.to_json
           },
           headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["ok"]).to be true
      expect(Automation::WebhookTestDelivery).to have_received(:call).with(
        url: "https://example.test/hook",
        http_method: "post",
        headers: "X-Test: 1",
        payload_template: { lead: { name: "{{nome}}" } }.to_json
      )
    end
  end
end

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
      lead = create(:lead, status: "Em Atendimento")
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

      post simulate_admin_automation_workflow_path(workflow), params: {
        automation_workflow: {
          name: "Simular",
          definition_json: definition.to_json
        }
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Simulação do builder")
      expect(response.body).to include(lead.display_name)
      expect(workflow.reload.status).to eq("draft")
    end
  end
end

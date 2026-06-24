require "rails_helper"

RSpec.describe AutomationWorkflow, type: :model do
  describe "#draft_version!" do
    it "cria uma versao rascunho com definicao padrao" do
      workflow = AutomationWorkflow.create!(name: "Resgate")

      version = workflow.draft_version!

      expect(version).to be_persisted
      expect(version.status).to eq("draft")
      expect(version.definition_hash[:nodes].first[:type]).to eq("entry")
      expect(version.definition_hash[:nodes].size).to eq(1)
      expect(version.definition_hash[:edges]).to eq([])
    end

    it "cria novo rascunho a partir da versao ativa publicada" do
      workflow = AutomationWorkflow.create!(name: "Resgate")
      version = workflow.draft_version!
      definition = {
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
        "edges" => [{ "from" => "entry_1", "to" => "action_1" }]
      }
      version.update!(definition: definition)
      workflow.publish!(version: version)

      draft = workflow.reload.draft_version!

      expect(draft.status).to eq("draft")
      expect(draft).not_to eq(version)
      expect(draft.definition_hash[:nodes].size).to eq(2)
      expect(draft.definition_hash[:nodes].last[:config][:action_type]).to eq("add_note")
      expect(draft.definition_hash[:edges]).to eq([{ "from" => "entry_1", "to" => "action_1" }])
    end

    it "recupera rascunho default criado apos publicacao sem sobrescrever edicoes reais" do
      workflow = AutomationWorkflow.create!(name: "Resgate")
      version = workflow.draft_version!
      definition = {
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
        "edges" => [{ "from" => "entry_1", "to" => "action_1" }]
      }
      version.update!(definition: definition)
      workflow.publish!(version: version)
      stale_draft = workflow.versions.create!(
        status: "draft",
        definition: Automation::WorkflowDefinition.default_definition
      )

      draft = workflow.reload.draft_version!

      expect(draft).to eq(stale_draft)
      expect(draft.definition_hash[:nodes].size).to eq(2)
      expect(draft.definition_hash[:nodes].last[:label]).to eq("Registrar nota")
    end
  end

  describe "#publish!" do
    it "publica a versao e ativa o fluxo" do
      workflow = AutomationWorkflow.create!(name: "Resgate")
      version = workflow.draft_version!
      version.update!(
        definition: {
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
          "edges" => [{ "from" => "entry_1", "to" => "action_1" }]
        }
      )

      workflow.publish!(version: version)

      expect(workflow.reload.status).to eq("active")
      expect(workflow.active_version).to eq(version)
      expect(version.reload.status).to eq("published")
      expect(version.published_at).to be_present
    end

    it "recusa publicar acao incompleta" do
      workflow = AutomationWorkflow.create!(name: "Incompleto")
      version = workflow.draft_version!
      version.update!(
        definition: {
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
              "label" => "Enviar WhatsApp",
              "config" => { "action_type" => "send_whatsapp" }
            }
          ],
          "edges" => [{ "from" => "entry_1", "to" => "action_1" }]
        }
      )

      expect { workflow.publish!(version: version) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(version.reload.validation_snapshot["errors"]).to include("tem acao de WhatsApp sem mensagem")
    end

    it "recusa definicao sem bloco de entrada" do
      workflow = AutomationWorkflow.create!(name: "Quebrado")
      version = workflow.versions.build(
        version_number: 1,
        status: "draft",
        definition: { "nodes" => [], "edges" => [] }
      )

      expect(version).not_to be_valid
      expect(version.errors[:definition]).to include("precisa ter ao menos um bloco de entrada")
    end
  end
end

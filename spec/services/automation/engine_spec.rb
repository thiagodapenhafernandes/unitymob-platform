require "rails_helper"

RSpec.describe "Automation engine" do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin, email: "auto-#{SecureRandom.hex(6)}@salute.test") }
  # let! garante o lead criado ANTES das regras, evitando que o gatilho lead_created
  # entre na fila antes da regra que cada exemplo está exercitando.
  let!(:lead) { create(:lead, admin_user: admin, status: "Em Atendimento") }

  describe Automation::ConditionMatcher do
    it "casa por etapa e tempo parado" do
      rule = AutomationRule.new(trigger_event: "lead_idle", conditions: { "stage" => "Em Atendimento", "idle_hours" => 1 })
      lead.update_column(:updated_at, 2.hours.ago)
      expect(Automation::ConditionMatcher.match?(rule, lead)).to be true
    end

    it "não casa quando a etapa difere" do
      rule = AutomationRule.new(trigger_event: "lead_idle", conditions: { "stage" => "Novo" })
      expect(Automation::ConditionMatcher.match?(rule, lead)).to be false
    end
  end

  describe Automation::ActionRunner do
    it "executa criar tarefa + nota + mover etapa; registra run e timeline" do
      rule = AutomationRule.create!(
        name: "R", trigger_event: "lead_created",
        actions: [
          { "type" => "create_task", "title" => "Ligar", "due_in_hours" => 2 },
          { "type" => "add_note", "body" => "via automação" },
          { "type" => "move_stage", "to" => "Concluido" }
        ]
      )

      expect {
        Automation::ActionRunner.run(rule, lead)
      }.to change(Task, :count).by(1).and change(AutomationRun, :count).by(1)

      expect(lead.reload.status).to eq("Concluido")
      expect(lead.tasks.first.title).to eq("Ligar")
      expect(lead.activities.where(kind: "task_created").count).to eq(1)
      expect(lead.activities.where(kind: "note").count).to eq(1)
      expect(AutomationRun.last.status).to eq("executed")
      expect(AutomationRun.last.automation_event).to be_nil
      expect(rule.reload.runs_count).to eq(1)
    end

    it "bloqueia mover para etapa controlada pela distribuição" do
      rule = AutomationRule.create!(
        name: "Nao represar", trigger_event: "lead_created",
        actions: [{ "type" => "move_stage", "to" => "Represado" }]
      )

      expect {
        Automation::ActionRunner.run(rule, lead)
      }.to change(AutomationRun, :count).by(1)

      expect(lead.reload.status).to eq("Em Atendimento")
      expect(AutomationRun.last.status).to eq("error")
      expect(AutomationRun.last.result["error"]).to include("Distribuicao de Leads")
    end

    it "agenda continuação no 'esperar' (nutrição) e só executa até o wait" do
      allow(Automation::RunActionsJob).to receive(:set).and_return(Automation::RunActionsJob)
      allow(Automation::RunActionsJob).to receive(:perform_later)

      rule = AutomationRule.create!(
        name: "drip", trigger_event: "lead_created",
        actions: [
          { "type" => "add_note", "body" => "dia 0" },
          { "type" => "wait", "days" => 2 },
          { "type" => "add_note", "body" => "dia 2" }
        ]
      )

      Automation::ActionRunner.run(rule, lead)

      expect(AutomationRun.last.status).to eq("scheduled")
      expect(lead.activities.where(kind: "note").count).to eq(1)
      expect(Automation::RunActionsJob).to have_received(:set).with(hash_including(:wait))
    end
  end

  describe Automation::Dispatcher do
    before { clear_enqueued_jobs }

    it "registra evento e enfileira processamento quando um lead é criado" do
      AutomationRule.create!(name: "novo", trigger_event: "lead_created", actions: [{ "type" => "add_note", "body" => "oi" }])

      expect {
        create(:lead)
      }.to change(AutomationEvent, :count).by(1)
        .and have_enqueued_job(Automation::ProcessEventJob)

      event = AutomationEvent.last
      expect(event.name).to eq("lead_created")
      expect(event.source).to eq("lead")
      expect(event.lead.activities.where(kind: "automation_event").count).to eq(1)
    end

    it "processa evento casado e vincula o run ao evento" do
      rule = AutomationRule.create!(name: "novo", trigger_event: "lead_created", actions: [{ "type" => "add_note", "body" => "oi" }])
      event = nil

      perform_enqueued_jobs do
        event = Automation::EventBus.emit(:lead_created, lead: lead, async: false)
      end

      expect(event.reload.status).to eq("processed")
      expect(AutomationRun.last.automation_rule).to eq(rule)
      expect(AutomationRun.last.automation_event).to eq(event)
      expect(lead.activities.where(kind: "note").last.metadata["body"]).to eq("oi")
    end
  end

  describe Automation::EventCatalog do
    it "centraliza os eventos conhecidos da plataforma" do
      expect(described_class.label("lead_idle")).to eq("Lead parado")
      expect(described_class.names).to include("lead_created", "lead_stage_changed", "proposal_viewed", "proposal_accepted", "whatsapp_received")
    end
  end

  describe Automation::Simulator do
    it "simula impacto sem executar ações" do
      lead.update_column(:updated_at, 3.hours.ago)
      AutomationRule.create!(name: "Conflito", trigger_event: "lead_idle", actions: [{ "type" => "add_note", "body" => "x" }])

      result = Automation::Simulator.rule(
        trigger_event: "lead_idle",
        conditions: { "stage" => "Em Atendimento", "idle_hours" => 1 },
        actions: [{ "type" => "move_stage", "to" => "Represado" }]
      )

      expect(result.candidate_count).to eq(1)
      expect(result.sample_leads).to include(lead)
      expect(result.actions.join).to include("mover")
      expect(result.warnings.join).to include("Distribuicao de Leads")
      expect(result.warnings.join).to include("ativa")
      expect(lead.reload.status).to eq("Em Atendimento")
    end
  end

  describe Automation::TickJob do
    before { clear_enqueued_jobs }

    it "emite evento para leads parados que casam as condições" do
      rule = AutomationRule.create!(
        name: "idle", trigger_event: "lead_idle",
        conditions: { "stage" => "Em Atendimento", "idle_hours" => 1 },
        actions: [{ "type" => "add_note", "body" => "parado" }]
      )
      lead.update_column(:updated_at, 3.hours.ago)

      expect {
        Automation::TickJob.new.perform
      }.to change(AutomationEvent.where(name: "lead_idle"), :count).by(1)
        .and have_enqueued_job(Automation::ProcessEventJob)

      event = AutomationEvent.where(name: "lead_idle").last
      expect(event.payload_hash[:automation_rule_id]).to eq(rule.id)
      expect(event.idempotency_key).to eq("lead_idle:rule:#{rule.id}:lead:#{lead.id}")
    end
  end
end

require "rails_helper"

RSpec.describe "Automation engine" do
  let(:admin) { create(:admin_user, :admin, email: "auto-#{SecureRandom.hex(6)}@salute.test") }
  # let! garante o lead criado ANTES das regras, evitando que o gatilho lead_created
  # dispare durante a criação do lead (adapter :async no test executaria a regra).
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
      expect(rule.reload.runs_count).to eq(1)
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
    it "dispara regra casada quando um lead é criado" do
      AutomationRule.create!(name: "novo", trigger_event: "lead_created", actions: [{ "type" => "add_note", "body" => "oi" }])
      allow(Automation::RunActionsJob).to receive(:perform_later)

      new_lead = create(:lead)

      expect(Automation::RunActionsJob).to have_received(:perform_later).with(kind_of(Integer), new_lead.id)
    end
  end

  describe Automation::TickJob do
    it "dispara para leads parados que casam as condições" do
      rule = AutomationRule.create!(
        name: "idle", trigger_event: "lead_idle",
        conditions: { "stage" => "Em Atendimento", "idle_hours" => 1 },
        actions: [{ "type" => "add_note", "body" => "parado" }]
      )
      lead.update_column(:updated_at, 3.hours.ago)
      allow(Automation::RunActionsJob).to receive(:perform_later)

      Automation::TickJob.new.perform

      expect(Automation::RunActionsJob).to have_received(:perform_later).with(rule.id, lead.id)
    end
  end
end

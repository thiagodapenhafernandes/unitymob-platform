require "rails_helper"

# Cobre o escopo por tenant do Dispatcher: uma regra de automação de UMA conta
# nao pode gerar fan-out de jobs para um lead/evento de OUTRA conta.
RSpec.describe Automation::Dispatcher do
  include ActiveJob::TestHelper

  let(:admin_a) { create(:admin_user, :admin, email: "disp-a-#{SecureRandom.hex(6)}@salute.test") }
  let(:tenant_a) { admin_a.tenant }
  let(:tenant_b) do
    Tenant.create!(name: "Tenant B #{SecureRandom.hex(3)}", slug: "tenant-b-#{SecureRandom.hex(3)}")
  end

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = tenant_a
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before { clear_enqueued_jobs }

  it "nao enfileira RunActionsJob para regra da conta A quando o evento e da conta B" do
    # Regra ativa vive na conta A.
    AutomationRule.create!(
      tenant: tenant_a,
      name: "Regra A",
      trigger_event: "lead_created",
      actions: [{ "type" => "add_note", "body" => "oi" }]
    )

    # Lead + evento pertencem a conta B.
    lead_b = create(:lead, tenant: tenant_b, name: "Lead B")
    event_b = AutomationEvent.create!(tenant: tenant_b, lead: lead_b, name: "lead_created", source: "lead")

    expect {
      Automation::Dispatcher.process_event(event_b)
    }.not_to have_enqueued_job(Automation::RunActionsJob)
  end

  it "enfileira RunActionsJob quando a regra e o evento sao da mesma conta" do
    rule = AutomationRule.create!(
      tenant: tenant_a,
      name: "Regra A",
      trigger_event: "lead_created",
      actions: [{ "type" => "add_note", "body" => "oi" }]
    )
    lead_a = create(:lead, admin_user: admin_a, name: "Lead A")
    event_a = AutomationEvent.create!(tenant: tenant_a, lead: lead_a, name: "lead_created", source: "lead")

    expect {
      Automation::Dispatcher.process_event(event_a)
    }.to have_enqueued_job(Automation::RunActionsJob).with(rule.id, lead_a.id, 0, event_a.id)
  end
end

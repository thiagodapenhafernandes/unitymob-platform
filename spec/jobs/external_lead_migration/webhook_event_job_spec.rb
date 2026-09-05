require "rails_helper"

RSpec.describe ExternalLeadMigration::WebhookEventJob do
  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant:) }
  let(:integration) { create(:external_lead_integration, tenant:, seller_mappings: { "seller" => broker.id }) }
  let(:client) { instance_double(ExternalLeadMigration::Client) }
  let(:payload) do
    { "data" => { "id" => "webhook-upsert", "attributes" => {
      "customer" => { "name" => "Cliente C2S", "phone" => "5547999991111" },
      "seller" => { "id" => "seller" },
      "schedulated_actions" => [{ "id" => "return", "schedulated_action_name" => "Retornar", "schedulated_action_date" => "2026-09-29T09:00:00-03:00" }]
    } } }
  end

  before do
    Current.tenant = tenant
    allow(ExternalLeadMigration::Client).to receive(:new).with(token: integration.access_token).and_return(client)
  end

  it "busca o evento resumido na API, cria e depois atualiza sem duplicar lead ou tarefa" do
    allow(client).to receive(:lead).with("webhook-upsert").and_return(payload)
    described_class.new.perform(integration.id, "lead_id" => "webhook-upsert")
    lead = tenant.leads.find_by!(external_lead_id: "webhook-upsert")
    task = lead.tasks.sole
    payload["data"]["attributes"]["customer"]["name"] = "Cliente atualizado"
    payload["data"]["attributes"]["schedulated_actions"][0]["schedulated_action_date"] = "2026-09-30T10:00:00-03:00"
    described_class.new.perform(integration.id, "lead_id" => "webhook-upsert")
    expect(tenant.leads.where(external_lead_id: "webhook-upsert").count).to eq(1)
    expect(lead.reload.name).to eq("Cliente atualizado")
    expect(lead.tasks.reload.pluck(:id)).to eq([task.id])
    expect(task.reload.due_at).to eq(Time.zone.parse("2026-09-30T10:00:00-03:00"))
  end

  it "propaga falha da API para retry sem criar um lead com dados incompletos" do
    allow(client).to receive(:lead).and_raise(ExternalLeadMigration::Client::Error, "API indisponível")
    expect {
      expect { described_class.new.perform(integration.id, "lead_id" => "webhook-upsert") }.to raise_error(ExternalLeadMigration::Client::Error)
    }.not_to change(Lead, :count)
  end
end

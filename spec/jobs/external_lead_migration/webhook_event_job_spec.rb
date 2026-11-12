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

  it "descarta RecordInvalid sem retry (validação nunca passa em retentativa)" do
    invalid = ActiveRecord::RecordInvalid.new(Lead.new)
    allow(ExternalLeadMigration::LeadUpsert).to receive(:call).and_raise(invalid)
    payload_with_attrs = { "data" => { "attributes" => { "customer" => { "name" => "Sem phone" } } } }

    expect {
      described_class.perform_now(integration.id, payload_with_attrs)
    }.not_to raise_error
    expect(Lead.count).to eq(0)
  end
  it "registra o filtro de nova modalidade sem falha ou cadastro vazio" do
    integration.update!(incoming_business_type: "sale")
    payload["data"]["attributes"]["product"] = { "negotiation_name" => "Locação" }
    expect { described_class.new.perform(integration.id, payload) }.not_to change { tenant.leads.count }
    expect(integration.reload.sync_message).to include("fora da modalidade")
    expect(integration.sync_status).to eq("completed")
  end

  it "completa eventos parciais no espelho antes de aplicar o corretor e a agenda" do
    integration.update!(mirror_c2s_owners: true)
    canonical = payload.deep_dup
    canonical["data"]["attributes"].merge!(
      "seller" => { "id" => "seller", "name" => broker.name, "email" => broker.email },
      "created_at" => 1.day.ago.iso8601, "updated_at" => Time.current.iso8601,
      "lead_status" => { "alias" => "under_negotiation" }, "funnel_status" => nil, "product" => {},
      "archive_details" => nil, "done_details" => nil, "done_deal_at" => nil, "last_activity_date" => nil, "is_favorite" => false
    )
    canonical["data"]["messages"] = []
    allow(client).to receive(:lead).with("webhook-upsert").and_return(canonical)
    partial = { "data" => { "id" => "webhook-upsert", "attributes" => { "customer" => { "name" => "Parcial" } } } }
    described_class.new.perform(integration.id, partial)
    lead = tenant.leads.find_by!(external_lead_id: "webhook-upsert")
    expect(lead.admin_user_id).to eq(broker.id)
    expect(lead.distribution_rule_id).to be_nil
    task_ids = lead.tasks.pluck(:id)
    described_class.new.perform(integration.id, canonical)
    expect(client).to have_received(:lead).once
    allow(client).to receive(:lead).and_raise(ExternalLeadMigration::Client::Error, "Indisponível")
    expect { described_class.new.perform(integration.id, partial) }.to raise_error(ExternalLeadMigration::Client::Error)
    expect(lead.reload.admin_user_id).to eq(broker.id)
    expect(lead.tasks.reload.pluck(:id)).to eq(task_ids)
  end

end

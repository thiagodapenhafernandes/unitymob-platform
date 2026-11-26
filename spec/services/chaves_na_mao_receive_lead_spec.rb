require "rails_helper"

RSpec.describe ChavesNaMao::ReceiveLead do
  let(:tenant) { create(:admin_user, :admin).tenant }
  let(:connection) { ChavesNaMaoConnection.create!(tenant: tenant, account_code: "33380", login_email: "cliente@example.com", integration_token: "x" * 40, enabled: true, operational: true) }
  let(:property) { create(:habitation, tenant: tenant, codigo: "CNM-1") }
  let(:payload) do
    { "id" => "12345", "name" => "Cliente Portal", "email" => "cliente-lead@example.com", "phone" => "11988776655",
      "message" => "Tenho interesse", "segment" => "REALTY", "createdAt" => "2026-11-26 10:00:00", "proposeTypeName" => "Formulário WhatsApp",
      "ad" => { "id" => "98765", "reference" => property.codigo, "title" => "Apartamento", "purpose" => "Venda" } }
  end
  let(:receipt) do
    connection.chaves_na_mao_lead_receipts.create!(event_id: payload["id"], payload_digest: SecureRandom.hex(32),
      payload: payload.to_json, received_at: Time.current, status: "pending")
  end

  before { LeadSetting.instance(tenant: tenant).update!(stickiness_match: "phone_or_email") }

  it "processes the official payload, links only this account's property and applies its portal queue" do
    site = create(:distribution_rule, tenant: tenant, source_site: true, distribution_mode: :shark_tank)
    portal = create(:distribution_rule, tenant: tenant, source_site: false, source_portal: true, distribution_mode: :shark_tank)
    ChavesNaMaoLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.status).to eq("processed")
    expect(receipt.lead).to have_attributes(property_id: property.id, distribution_rule_id: portal.id, attribution_source: "chaves_na_mao")
    expect(receipt.lead.business_type).to eq("venda")
    expect(receipt.lead.property_interests.where(habitation: property)).to exist
    expect(receipt.payload_before_type_cast).not_to include("cliente-lead@example.com")
    expect(connection.reload.last_lead_received_at).to be_present
    expect(receipt.lead.distribution_rule_id).not_to eq(site.id)
    expect { ChavesNaMaoLeadProcessingJob.perform_now(receipt.id) }.not_to change(Lead, :count)
  end

  it "uses rental rules instead of sale or site rules" do
    payload["ad"]["purpose"] = "Locação"
    create(:distribution_rule, tenant: tenant, source_portal: true, source_site: false, business_type: :venda, distribution_mode: :shark_tank)
    rental = create(:distribution_rule, tenant: tenant, source_portal: true, source_site: false, business_type: :locacao, distribution_mode: :shark_tank)
    described_class.call(receipt)
    expect(receipt.reload.lead.distribution_rule_id).to eq(rental.id)
    expect(receipt.lead.business_type).to eq("locacao")
  end

  it "receives directly without a C2S connection and assigns the account's configured agent" do
    expect(ExternalLeadIntegration.where(tenant: tenant)).not_to exist
    owner = create(:admin_user, tenant: tenant)
    rule = create(:distribution_rule, tenant: tenant, source_site: false, source_portal: true)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: owner)
    expect { described_class.call(receipt) }.not_to have_enqueued_job(ExternalLeadMigration::ExportLeadJob)
    expect(receipt.reload.lead).to have_attributes(distribution_rule_id: rule.id, admin_user_id: owner.id)
  end

  it "preserves daily rental configured on this account's property" do
    property.update!(status: "Diária")
    payload["ad"]["purpose"] = "Locação"
    described_class.call(receipt)
    expect(receipt.reload.lead.business_type).to eq("diaria")
  end

  it "preserves the mirrored C2S owner and history when complementing a contact" do
    owner = create(:admin_user, tenant: tenant)
    integration = create(:external_lead_integration, tenant: tenant, connected_by_admin_user: owner,
      operational_mappings: { "mirror_c2s_owners" => true })
    original = create(:lead, tenant: tenant, phone: payload["phone"], email: payload["email"], admin_user: owner,
      property_id: property.id, notes: "Histórico anterior", origin: "Migração externa",
      external_lead_integration: integration, external_lead_id: "existing-c2s")
    previous = original.attributes.slice("admin_user_id", "status", "property_id", "origin", "notes", "external_lead_id")
    expect { described_class.call(receipt) }.not_to have_enqueued_job(ExternalLeadMigration::ExportLeadJob)
    expect(receipt.reload.lead_id).to eq(original.id)
    expect(original.reload.attributes.slice(*previous.keys)).to eq(previous)
  end

  it "keeps mixed purpose and accepts an email-only contact" do
    payload["ad"]["purpose"] = "Venda/Locação"
    payload["phone"] = nil
    described_class.call(receipt)
    expect(receipt.reload.status).to eq("processed")
    expect(receipt.lead.business_type).to eq("ambos")
  end

  it "keeps an unknown reference without borrowing a different account's property or settings" do
    other = Tenant.create!(name: "Outra", slug: "chaves-other-#{SecureRandom.hex(4)}")
    create(:habitation, tenant: other, codigo: "OUTRO-1")
    payload["ad"]["reference"] = "OUTRO-1"
    described_class.call(receipt)
    expect(receipt.reload.status).to eq("processed")
    expect(receipt.lead.tenant_id).to eq(tenant.id)
    expect(receipt.lead.property_id).to be_nil
    expect(receipt.lead.notes).to include("OUTRO-1")
  end

  it "handles a null reference without using the portal listing ID as a local ID" do
    payload["ad"]["reference"] = nil
    payload["ad"]["id"] = property.id.to_s
    described_class.call(receipt)
    expect(receipt.reload.lead.property_id).to be_nil
  end

  it "quarantines malformed contacts and segments without creating leads" do
    payload["segment"] = "VEHICLE"
    expect { described_class.call(receipt) }.not_to change(Lead, :count)
    expect(receipt.reload).to have_attributes(status: "quarantined", reason: "invalid_payload")
    payload["segment"] = "REALTY"
    payload["phone"] = nil
    payload["email"] = "invalid"
    receipt.update!(payload: payload.to_json, status: "pending")
    expect { described_class.call(receipt) }.not_to change(Lead, :count)
    expect(receipt.reload.reason).to eq("missing_contact")
  end

  it "never replays historical capture and respects disabling before job execution" do
    receipt.update!(status: "captured")
    expect { described_class.call(receipt) }.not_to change(Lead, :count)
    receipt.update!(status: "pending")
    connection.update!(enabled: false)
    expect { described_class.call(receipt) }.not_to change(Lead, :count)
    expect(receipt.reload.reason).to eq("receiving_disabled")
  end

  it "complements an existing contact and makes replay inert even after complementing" do
    existing = create(:lead, tenant: tenant, phone: payload["phone"], email: payload["email"])
    expect { described_class.call(receipt) }.not_to change(Lead, :count)
    expect(receipt.reload.lead_id).to eq(existing.id)
    expect(existing.activities.where(kind: "inquiry_complemented").count).to eq(1)
    receipt.update!(status: "pending")
    expect { described_class.call(receipt) }.not_to change { existing.activities.count }
  end
end

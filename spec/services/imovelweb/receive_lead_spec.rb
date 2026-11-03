require "rails_helper"

RSpec.describe Imovelweb::ReceiveLead do
  let(:tenant) { create(:admin_user, :admin).tenant }
  let(:connection) { ImovelwebConnection.create!(tenant: tenant, client_code: SecureRandom.uuid, enabled: true, authorized_at: Time.current) }
  let(:property) { create(:habitation, tenant: tenant, codigo: "IW-1") }
  let(:payload) { { "event_id" => "event-1", "event_type" => "CONTACTO_MENSAJE", "client_code" => connection.client_code, "environment" => "sandbox", "reference" => "IW-1", "name" => "Cliente", "email" => "imovelweb@example.com", "message" => "Tenho interesse" } }
  let(:receipt) { connection.imovelweb_lead_receipts.create!(event_id: payload.fetch("event_id"), event_type: payload.fetch("event_type"), payload: payload.to_json, received_at: Time.current) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("IMOVELWEB_RECEIVING_ENABLED").and_return("true")
    LeadSetting.instance(tenant: tenant).update!(stickiness_match: "phone_or_email")
    connection.imovelweb_listings.create!(habitation: property, reference: "IW-1", external_id: "123")
  end

  it "processes an email-only lead once, encrypts the receipt and confirms only this connection" do
    other = PortalIntegration.for_portal!("imovelweb", tenant: tenant)
    previous = other.last_lead_at
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.status).to eq("processed")
    expect(receipt.lead.attribution_source).to eq("imovelweb")
    expect(receipt.lead.property_id).to eq(property.id)
    expect(receipt.lead.property_interests.where(habitation: property)).to exist
    expect(receipt.payload_before_type_cast).not_to include("imovelweb@example.com")
    expect(connection.reload.last_lead_received_at).to be_present
    expect(other.reload.last_lead_at).to eq(previous)
    expect { ImovelwebLeadProcessingJob.perform_now(receipt.id) }.not_to change(Lead, :count)
  end

  it "records a distinct inquiry for the same contact and makes replay inert" do
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    second = connection.imovelweb_lead_receipts.create!(event_id: "event-2", event_type: "CONTACTO_MENSAJE", payload: payload.merge("event_id" => "event-2").to_json, received_at: Time.current)
    expect { ImovelwebLeadProcessingJob.perform_now(second.id) }.not_to change(Lead, :count)
    expect(second.reload.lead_id).to eq(receipt.reload.lead_id)
    activities = second.lead.activities.where(kind: "inquiry_complemented")
    count = activities.count
    expect(count).to be > 0
    ImovelwebLeadProcessingJob.perform_now(second.id)
    expect(activities.count).to eq(count)
  end

  it "uses the existing portal distribution rule" do
    rule = create(:distribution_rule, tenant: tenant, source_site: false, source_portal: true, distribution_mode: :shark_tank)
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.lead.distribution_rule_id).to eq(rule.id)
    expect(receipt.lead.activities.where(kind: "shark_tank_ready")).to exist
  end

  it "quarantines unknown listings and never searches another tenant" do
    payload["reference"] = "NOT-MAPPED"
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.reason).to eq("unknown_listing")
    expect(receipt.lead_id).to be_nil
  end

  it "rejects mapping a property from another tenant" do
    other = Tenant.create!(name: "Outro", slug: "iw-other")
    foreign_property = create(:habitation, tenant: other)
    mapping = connection.imovelweb_listings.new(habitation: foreign_property, reference: "foreign")
    expect(mapping).not_to be_valid
  end

  it "quarantines mismatched account, missing contact and conflicting references" do
    payload["client_code"] = "foreign"
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.reason).to eq("invalid_payload")
    receipt.update!(status: "pending", payload: payload.merge("client_code" => connection.client_code, "email" => "invalid").to_json)
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.reason).to eq("missing_contact")
    connection.imovelweb_listings.create!(habitation: property, reference: "other", external_id: "456")
    receipt.update!(status: "pending", payload: payload.merge("client_code" => connection.client_code, "listing_id" => "456").to_json)
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.reason).to eq("conflicting_listing")
  end

  it "rolls back lead creation if confirming the connection fails validation" do
    expect_any_instance_of(ImovelwebConnection).to receive(:update!).with(last_lead_received_at: anything).and_raise(ActiveRecord::RecordInvalid.new(Lead.new))
    expect { ImovelwebLeadProcessingJob.perform_now(receipt.id) }.not_to change(Lead, :count)
    expect(receipt.reload.status).to eq("quarantined")
    expect(receipt.lead_id).to be_nil
  end

  it "resolves identical listing codes only inside the owning tenant" do
    other = Tenant.create!(name: "Outra conta", slug: "iw-identical-code")
    other_property = create(:habitation, tenant: other, codigo: property.codigo)
    other_connection = ImovelwebConnection.create!(tenant: other, client_code: "other-client", enabled: true, authorized_at: Time.current)
    other_connection.imovelweb_listings.create!(habitation: other_property, reference: "IW-1")
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.lead.tenant_id).to eq(tenant.id)
    expect(receipt.lead.property_id).to eq(property.id)
    expect(other.leads).to be_empty
  end

  it "does not process pending events while disabled" do
    connection.update!(enabled: false)
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.status).to eq("pending")
    expect(receipt.lead_id).to be_nil
  end

  it "defaults to sandbox and disabled and protects identity" do
    prepared = ImovelwebConnection.create!(tenant: tenant, client_code: "another-code")
    expect(prepared.environment).to eq("sandbox")
    expect(prepared).not_to be_receiving
    expect(prepared.update(client_code: "changed")).to eq(false)
  end

  it "routes as portal without matching a site-only rule and permits only provider-scoped email-only leads" do
    lead = build(:lead, tenant: tenant, phone: nil, email: "imovelweb@example.com", origin: "Imovelweb", attribution_source: "imovelweb", attribution_channel: "portal",
      attribution_data: { "provider" => "imovelweb_direct" }, other_information: { "imovelweb_event_id" => "event" })
    expect(lead).to be_valid
    distributor = Leads::DistributorService.new(lead)
    rule = build(:distribution_rule, tenant: tenant, source_portal: true, source_site: false)
    expect(distributor.send(:matches_source?, rule)).to eq(true)
    rule.assign_attributes(source_portal: false, source_site: true)
    expect(distributor.send(:matches_source?, rule)).to eq(false)
    lead.attribution_source = "grupozap"
    expect(lead).not_to be_valid
  end
end

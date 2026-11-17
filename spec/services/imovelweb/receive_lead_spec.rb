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
    expect(receipt.lead.notes).to include("Referência do imóvel: IW-1", "Tenho interesse")
    expect(receipt.lead.other_information["origin_listing_reference"]).to eq("IW-1")
    expect(receipt.payload_before_type_cast).not_to include("imovelweb@example.com")
    expect(connection.reload.last_lead_received_at).to be_present
    expect(other.reload.last_lead_at).to eq(previous)
    expect { ImovelwebLeadProcessingJob.perform_now(receipt.id) }.not_to change(Lead, :count)
  end

  it "records a distinct inquiry for the same contact and makes replay inert" do
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    second = connection.imovelweb_lead_receipts.create!(event_id: "event-2", event_type: "CONTACTO_MENSAJE",
      payload: payload.merge("event_id" => "event-2", "reference" => "SEM-MAPA", "listing_id" => "789", "message" => "Quero visitar outro anúncio").to_json, received_at: Time.current)
    expect { ImovelwebLeadProcessingJob.perform_now(second.id) }.not_to change(Lead, :count)
    expect(second.reload.lead_id).to eq(receipt.reload.lead_id)
    activities = second.lead.activities.where(kind: "inquiry_complemented")
    expect(second.lead.property_id).to eq(property.id)
    expect(second.lead.notes).to include("Referência do imóvel: IW-1")
    expect(activities.last.metadata).to include("body" => a_string_including("Referência do imóvel: SEM-MAPA", "ID do anúncio: 789", "Quero visitar outro anúncio"))
    expect(activities.last.metadata.dig("inquiry_information", "origin_listing_reference")).to eq("SEM-MAPA")
    count = activities.count
    expect(count).to be > 0
    second.update!(status: "pending")
    ImovelwebLeadProcessingJob.perform_now(second.id)
    expect(activities.count).to eq(count)
  end

  it "attaches a provider retry of an API-recovered query without routing or notifying again" do
    payload.merge!("listing_id" => "123", "registered_at" => "2026-11-17T13:52:45Z", "contact_type" => "10")
    original = create(:lead, tenant: tenant, email: payload["email"], status: "Desqualificado | Arquivar")
    fingerprint = described_class.recovery_fingerprint(connection, payload)
    original.activities.create!(tenant: tenant, kind: "inquiry_complemented", metadata: { "ingress_reference" => "imovelweb:recovery:#{fingerprint}" })
    previous = original.attributes
    expect(Leads::Intake).not_to receive(:create!)
    expect(Leads::NotificationDispatcher).not_to receive(:notify_complement)
    expect { described_class.call(receipt) }.not_to change(Lead, :count)
    expect(receipt.reload.lead_id).to eq(original.id)
    expect(original.reload.attributes).to eq(previous)
    equivalent = payload.merge("registered_at" => "2026-11-17T08:52:45-0500")
    expect(described_class.recovery_fingerprint(connection, equivalent)).to eq(fingerprint)
    expect(described_class.recovery_fingerprint(connection, payload.merge("registered_at" => "invalid"))).to be_nil
    expect(described_class.recovery_fingerprint(connection, payload.merge("registered_at" => "2026-11-17T13:53:45Z"))).not_to eq(fingerprint)
  end

  it "keeps the portal origin metadata without changing the integration identity" do
    payload['lead_origin'] = 'Wimoveis'
    described_class.call(receipt)
    expect(receipt.reload.lead.other_information['lead_origin']).to eq('Wimoveis')
    expect(receipt.lead.attribution_source).to eq('imovelweb')
  end

  it "keeps both Navent references and links the property by its original code" do
    payload['portal_reference'] = 'iw-123'
    described_class.call(receipt)
    expect(receipt.reload.status).to eq('processed')
    expect(receipt.lead.property_id).to eq(property.id)
    expect(receipt.lead.other_information).to include('origin_listing_reference' => 'IW-1', 'portal_listing_reference' => 'iw-123')
    expect(receipt.lead.notes).to include('Referência do imóvel: IW-1', 'Referência da integração no portal: iw-123')
  end

  it "links an original code from this tenant when there is no listing mapping" do
    connection.imovelweb_listings.destroy_all
    payload.merge!('listing_id' => '123', 'portal_reference' => 'iw-123')
    described_class.call(receipt)
    expect(receipt.reload.status).to eq('processed')
    expect(receipt.lead.property_id).to eq(property.id)
    expect(receipt.lead.property_interests.where(habitation: property)).to exist
  end

  it "uses the existing portal distribution rule" do
    rule = create(:distribution_rule, tenant: tenant, source_site: false, source_portal: true, distribution_mode: :shark_tank)
    payload["reference"] = "SEM-MAPA"
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.lead.distribution_rule_id).to eq(rule.id)
    expect(receipt.lead.property_id).to be_nil
    expect(receipt.lead.activities.where(kind: "shark_tank_ready")).to exist
  end

  it "complements an existing C2S contact without replacing its owner, property or history" do
    owner = create(:admin_user, tenant: tenant)
    integration = create(:external_lead_integration, tenant: tenant, connected_by_admin_user: owner,
      operational_mappings: { "mirror_c2s_owners" => true })
    original = create(:lead, tenant: tenant, email: payload["email"], admin_user: owner,
      property_id: property.id, notes: "Histórico anterior", origin: "Migração externa",
      external_lead_integration: integration, external_lead_id: "existing-c2s")
    previous = original.attributes.slice("admin_user_id", "status", "property_id", "origin", "notes", "external_lead_id")
    payload.merge!("reference" => "SEM-MAPA", "listing_id" => "789")

    expect { ImovelwebLeadProcessingJob.perform_now(receipt.id) }.not_to change { tenant.leads.count }
    expect(receipt.reload.lead_id).to eq(original.id)
    expect(original.reload.attributes.slice(*previous.keys)).to eq(previous)
    expect(original.activities.find_by!(kind: "inquiry_complemented").metadata).to include(
      "body" => a_string_including("Referência do imóvel: SEM-MAPA", "ID do anúncio: 789", "Tenho interesse"))
    expect(ExternalLeadMigration::ExportLeadJob).not_to have_been_enqueued
  end

  it "receives an unmapped listing with its context without searching another tenant" do
    other = Tenant.create!(name: "Outra conta", slug: "iw-unmapped")
    foreign_property = create(:habitation, tenant: other, codigo: "NOT-MAPPED")
    foreign_connection = ImovelwebConnection.create!(tenant: other, client_code: "foreign-unmapped")
    foreign_connection.imovelweb_listings.create!(habitation: foreign_property, reference: "NOT-MAPPED", external_id: "987")
    payload["reference"] = "NOT-MAPPED"
    payload["listing_id"] = "987"
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.status).to eq("processed")
    expect(receipt.reason).to be_nil
    expect(receipt.lead).to have_attributes(tenant_id: tenant.id, property_id: nil, product: nil)
    expect(receipt.lead.property_interests).to be_empty
    expect(receipt.lead.notes).to include("Referência do imóvel: NOT-MAPPED", "ID do anúncio: 987", "Tenho interesse")
    expect(receipt.lead.other_information).to include("origin_listing_reference" => "NOT-MAPPED", "origin_listing_id" => "987", "portal_message" => "Tenho interesse")
    expect(other.leads).to be_empty
    expect { ImovelwebLeadProcessingJob.perform_now(receipt.id) }.not_to change(Lead, :count)
  end

  it "receives a valid contact even without listing identifiers" do
    payload.delete("reference")
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.status).to eq("processed")
    expect(receipt.lead.property_id).to be_nil
    expect(receipt.lead.notes).to eq("Contato recebido pelo Imovelweb\nTenho interesse")
  end

  it "resolves a mapped listing by external ID without a reference" do
    payload.delete("reference")
    payload["listing_id"] = "123"
    ImovelwebLeadProcessingJob.perform_now(receipt.id)
    expect(receipt.reload.lead.property_id).to eq(property.id)
  end

  it "retains an invalid cross-tenant mapping instead of assigning a foreign property" do
    other = Tenant.create!(name: "Outra conta", slug: "iw-invalid-map")
    foreign_property = create(:habitation, tenant: other)
    connection.imovelweb_listings.find_by!(reference: "IW-1").update_column(:habitation_id, foreign_property.id)
    expect { ImovelwebLeadProcessingJob.perform_now(receipt.id) }.not_to change(Lead, :count)
    expect(receipt.reload.reason).to eq("conflicting_listing")
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

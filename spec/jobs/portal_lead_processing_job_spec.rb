require "rails_helper"

RSpec.describe PortalLeadProcessingJob, type: :job do
  before { allow_any_instance_of(Lead).to receive(:route_lead) }

  let(:tenant) { Tenant.default }

  def payload(overrides = {})
    {
      "leadOrigin" => "Grupo OLX",
      "originLeadId" => "lead-abc",
      "originListingId" => "87027856",
      "clientListingId" => "ZAP-100",
      "name" => "Maria Silva",
      "email" => "maria@example.test",
      "phoneNumber" => "47999999999",
      "message" => "Tenho interesse.",
      "temperature" => "Alta",
      "transactionType" => "SELL",
      "extraData" => { "leadType" => "CONTACT_CHAT" }
    }.merge(overrides)
  end

  def enable_leads!(tenant, portal: "zapimoveis")
    integration = PortalIntegration.for_portal!(portal, tenant: tenant)
    integration.update!(enabled: true, leads_enabled: true, account_id: "42")
    integration
  end

  it "cria lead sem corretor vinculado ao imóvel" do
    property = create(:habitation, tenant: tenant, codigo: "ZAP-100")
    enable_leads!(tenant)

    expect { described_class.perform_now(payload) }.to change { tenant.leads.count }.by(1)

    lead = tenant.leads.last
    expect(lead.admin_user).to be_nil
    expect(lead.origin).to eq("grupo_zap")
    expect(lead.attribution_channel).to eq("portal")
    expect(lead.property_id).to eq(property.id)
    expect(lead.phone).to eq("5547999999999")
    expect(lead.other_information["portal_lead_id"]).to eq("lead-abc")
    expect(lead.property_interests.map(&:habitation_id)).to include(property.id)
  end

  it "não duplica reentrega do mesmo originLeadId" do
    create(:habitation, tenant: tenant, codigo: "ZAP-100")
    enable_leads!(tenant)

    described_class.perform_now(payload)
    expect { described_class.perform_now(payload) }.not_to(change { tenant.leads.count })
  end

  it "descarta quando recebimento desligado, sem criar lead" do
    create(:habitation, tenant: tenant, codigo: "ZAP-100")
    PortalIntegration.for_portal!("zapimoveis", tenant: tenant).update!(enabled: true, leads_enabled: false)

    expect { described_class.perform_now(payload) }.not_to(change { Lead.count })
    event = PortalIntegrationEvent.last
    expect(event.normalized_status).to eq("leads_disabled")
    expect(event.tenant).to eq(tenant)
  end

  it "quarentena imóvel desconhecido sem tenant" do
    expect { described_class.perform_now(payload) }.not_to(change { Lead.count })
    event = PortalIntegrationEvent.last
    expect(event.event_type).to eq("lead_quarantined")
    expect(event.normalized_status).to eq("unknown_listing")
    expect(event.tenant).to be_nil
  end

  it "quarentena código ambíguo entre contas sem adivinhar" do
    other = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(4)}")
    create(:habitation, tenant: tenant, codigo: "DUP-1")
    create(:habitation, tenant: other, codigo: "DUP-1")
    enable_leads!(tenant)

    expect { described_class.perform_now(payload("clientListingId" => "DUP-1")) }.not_to(change { Lead.count })
    event = PortalIntegrationEvent.last
    expect(event.normalized_status).to eq("ambiguous_listing")
    expect(event.raw_payload["tenant_ids"]).to contain_exactly(tenant.id, other.id)
  end

  it "quarentena MCMV sem anúncio" do
    mcmv = payload("clientListingId" => nil, "originListingId" => nil,
                   "extraData" => { "mcmv" => { "sellerDocument" => "12345678000190" } })

    expect { described_class.perform_now(mcmv) }.not_to(change { Lead.count })
    expect(PortalIntegrationEvent.last.normalized_status).to eq("mcmv_no_listing")
  end

  it "atualiza último lead das integrações OLX da conta" do
    create(:habitation, tenant: tenant, codigo: "ZAP-100")
    zap = enable_leads!(tenant, portal: "zapimoveis")
    viva = enable_leads!(tenant, portal: "vivareal_vrsync")

    described_class.perform_now(payload)

    expect(zap.reload.last_lead_at).to be_present
    expect(viva.reload.last_lead_at).to be_present
  end
end

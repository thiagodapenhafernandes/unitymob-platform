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

  it "reutiliza o lead C2S quando ele chega antes, sem alterar responsável e status" do
    property = create(:habitation, tenant: tenant, codigo: "ZAP-100")
    enable_leads!(tenant)
    external = create(:external_lead_integration, tenant: tenant)
    broker = create(:admin_user, tenant: tenant)
    original = create(:lead, tenant: tenant, property_id: property.id, phone: "47999999999",
      email: "maria@example.test", admin_user: broker, status: "Em Atendimento",
      external_lead_integration: external, external_lead_id: "c2s-original",
      attribution_source: "Grupo Zap", other_information: { "external_lead_id" => "c2s-original" })
    expect { 2.times { described_class.perform_now(payload) } }.not_to change { tenant.leads.count }
    original.reload
    expect(original.other_information["portal_lead_id"]).to eq("lead-abc")
    expect(original.other_information["external_lead_id"]).to eq("c2s-original")
    expect(original.origin).to eq("site")
    expect(original.admin_user_id).to eq(broker.id)
    expect(original.status).to eq("Em Atendimento")
  end

  it "acrescenta outro imóvel ao contato sem afetar outra conta" do
    property = create(:habitation, tenant: tenant, codigo: "ZAP-100")
    enable_leads!(tenant)
    external = create(:external_lead_integration, tenant: tenant)
    different_property = create(:habitation, tenant: tenant)
    original = create(:lead, tenant: tenant, property_id: different_property.id, phone: "47999999999",
      email: "maria@example.test", external_lead_integration: external, attribution_source: "Grupo Zap")
    other = Tenant.create!(name: "Outra", slug: "olx-other-#{SecureRandom.hex(3)}")
    create(:lead, tenant: other, phone: "47999999999", email: "maria@example.test")
    expect { described_class.perform_now(payload) }.not_to change { tenant.leads.count }
    expect(original.reload.property_id).to eq(different_property.id)
    expect(original.property_interests.pluck(:habitation_id)).to include(property.id)
    expect(other.leads.count).to eq(1)
  end

  it "resolve códigos repetidos somente dentro da conta da integração" do
    property = create(:habitation, tenant: tenant, codigo: "ZAP-100")
    other = Tenant.create!(name: "Outra conta", slug: "outra-#{SecureRandom.hex(4)}")
    create(:habitation, tenant: other, codigo: "ZAP-100")
    integration = enable_leads!(tenant)
    described_class.perform_now(payload, integration.id)
    expect(tenant.leads.last.property_id).to eq(property.id)
    expect(other.leads.count).to eq(0)
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

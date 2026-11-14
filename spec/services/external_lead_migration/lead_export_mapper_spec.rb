require "rails_helper"

RSpec.describe ExternalLeadMigration::LeadExportMapper do
  let(:tenant) { Tenant.default }
  let(:property) { create(:habitation, tenant: tenant, codigo: "AP-9001") }

  it "segue o envelope de criação documentado pelo C2S" do
    lead = create(:lead, tenant: tenant, name: "Maria", phone: "+55 48 98851-6745", email: "maria@example.test",
      origin: "Site", product: "Apartamento", property_id: property.id)
    payload = described_class.call(lead: lead)
    expect(payload.dig("data", "type")).to eq("lead")
    expect(payload.dig("data", "attributes")).to include(
      "name" => "Maria", "email" => "maria@example.test", "phone" => "5548988516745",
      "source" => "Site", "prop_ref" => "AP-9001", "description" => property.display_title.truncate(250),
      "external_id" => "unitymob:#{tenant.id}:#{lead.id}")
    expect(payload.dig("data", "attributes")).not_to have_key("seller")
    expect(payload).not_to have_key("customer")
  end

  it "envia o valor documentado para imóvel sem código e limita a descrição" do
    lead = build(:lead, tenant: tenant, name: "José", phone: "47999990000", email: "", product: "X" * 300)
    attributes = described_class.call(lead: lead).dig("data", "attributes")
    expect(attributes).to include("name" => "José", "phone" => "5547999990000", "prop_ref" => "Sem código")
    expect(attributes).not_to have_key("email")
    expect(attributes["description"].length).to eq(250)
  end

  it "não consulta imóveis de outra conta" do
    foreign = create(:habitation, tenant: Tenant.create!(name: "Outra", slug: "c2s-mapper-#{SecureRandom.hex(3)}"))
    lead = build(:lead, tenant: tenant, property_id: foreign.id)
    expect(described_class.call(lead: lead).dig("data", "attributes", "prop_ref")).to eq("Sem código")
  end

  it "exige ao menos um contato" do
    lead = build(:lead, tenant: tenant, phone: nil, email: nil)
    expect { described_class.call(lead: lead) }.to raise_error(ArgumentError, "C2S exige telefone ou e-mail")
  end

  it "identifica um contato novo de campanha sem mudar sua origem local" do
    lead = build(:lead, tenant: tenant, origin: "whatsapp_campaign")
    attrs = described_class.call(lead: lead).dig("data", "attributes")
    expect(attrs).to include("source" => "Disparo de WhatsApp", "observation" => include("Origem: Disparo de WhatsApp"))
  end

  it "usa a resposta positiva da campanha para exportar lead antigo de Site" do
    admin = create(:admin_user, :admin, tenant: tenant)
    create(:external_lead_integration, tenant: tenant)
    rule = create(:distribution_rule, tenant: tenant, delivery_destination: "c2s", source_whatsapp_campaign: true)
    template = WhatsappTemplate.create!(tenant: tenant, name: "source_test", status: "APPROVED", body: "Olá",
      buttons: {"0" => {"kind" => "quick_reply", "text" => "Estou buscando"}})
    campaign = tenant.whatsapp_campaigns.create!(name: "Locação", created_by: admin, whatsapp_template: template,
      response_decisions: {buttons: [{key: template.interactive_buttons.first["key"], action: "generate_lead", distribution_rule_id: rule.id}]})
    lead = create(:lead, tenant: tenant, origin: "Site", distribution_rule: rule, skip_automatic_routing: true)
    message = campaign.campaign_messages.create!(lead: lead, phone_number: lead.phone, status: "replied",
      reply_button_text: "Estou buscando", reply_button_payload: template.interactive_buttons.first["key"])

    expect(described_class.call(lead: lead).dig("data", "attributes", "source")).to eq("Disparo de WhatsApp")
    expect(lead.reload.origin).to eq("Site")
    message.update!(reply_button_text: "Outro", reply_button_payload: nil)
    expect(described_class.call(lead: lead).dig("data", "attributes", "source")).to eq("Site")
  end
end

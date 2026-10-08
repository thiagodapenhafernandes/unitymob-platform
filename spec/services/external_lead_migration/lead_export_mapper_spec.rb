require "rails_helper"

RSpec.describe ExternalLeadMigration::LeadExportMapper do
  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant:, email: "corretor@example.test", name: "Corretor") }
  let(:property) { create(:habitation, tenant:, codigo: "AP-9001") }

  it "monta o payload de exportação com cliente, origem e referência rastreável" do
    lead = create(:lead, tenant:, name: "Maria", phone: "+55 48 98851-6745", email: "maria@example.test",
      origin: "Site", product: "Apartamento", property_id: property.id, admin_user: broker)

    payload = described_class.call(lead:)

    expect(payload["customer"]).to include("name" => "Maria", "email" => "maria@example.test", "phone" => "5548988516745")
    expect(payload["lead_source"]).to eq("name" => "Site")
    expect(payload["seller"]).to eq("email" => "corretor@example.test", "name" => "Corretor")
    expect(payload["description"]).to eq(property.display_title)
    expect(payload["observation"]).to include("Origem: Site")
    expect(payload["external_reference"]).to eq("unitymob:#{tenant.id}:#{lead.id}")
    expect(payload["custom_attributes"]).to include("unitymob_lead_id" => lead.id, "unitymob_property_code" => "AP-9001")
  end

  it "funciona sem corretor, imóvel ou e-mail" do
    lead = create(:lead, tenant:, name: "José", phone: "47999990000", email: "")

    payload = described_class.call(lead:)

    expect(payload["customer"]).to include("name" => "José", "phone" => "5547999990000")
    expect(payload["customer"]).not_to have_key("email")
    expect(payload["seller"]).to be_nil
    expect(payload["external_reference"]).to eq("unitymob:#{tenant.id}:#{lead.id}")
  end
end

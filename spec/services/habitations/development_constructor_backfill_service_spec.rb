require "rails_helper"

RSpec.describe Habitations::DevelopmentConstructorBackfillService do
  it "não sugere construtora a partir de empreendimento de outro tenant" do
    current_tenant = Tenant.create!(name: "Tenant constructor #{SecureRandom.hex(3)}", slug: "tenant-constructor-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro constructor #{SecureRandom.hex(3)}", slug: "outro-constructor-#{SecureRandom.hex(3)}")
    constructor = Constructor.create!(name: "Construtora Externa")
    create(:habitation, tenant: other_tenant, codigo: "DEV-CTOR-OUT", tipo: "Empreendimento", categoria: "Empreendimento", nome_empreendimento: "Residencial Mesmo Nome", constructor: constructor)
    development = create(:habitation, tenant: current_tenant, codigo: "DEV-CTOR-CUR", tipo: "Empreendimento", categoria: "Empreendimento", nome_empreendimento: "Residencial Mesmo Nome", constructor: nil)

    result = described_class.new(tenant: current_tenant).call

    row = result.rows.find { |item| item[:development_id] == development.id }
    expect(row).to be_present
    expect(row[:suggested_constructor_id]).to be_nil
  end
end

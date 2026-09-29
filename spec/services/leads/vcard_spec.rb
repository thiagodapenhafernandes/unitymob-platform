require "rails_helper"

RSpec.describe Leads::Vcard do
  let(:tenant) { Tenant.create!(name: "Tenant vCard #{SecureRandom.hex(3)}", slug: "tenant-vcard-#{SecureRandom.hex(3)}") }

  it "gera vCard com nome padronizado, telefone e e-mail" do
    lead = create(:lead, tenant: tenant, name: "João da Silva",
      phone: "5515997750237", email: "joao@example.com")

    content = described_class.content(lead)

    expect(content).to include("BEGIN:VCARD")
    expect(content).to include("FN:[Unitymob] João da Silva")
    expect(content).to include("TEL;TYPE=CELL,VOICE:+5515997750237")
    expect(content).to include("EMAIL:joao@example.com")
    expect(content).to include("END:VCARD")
  end

  it "escapa caracteres especiais do vCard" do
    lead = create(:lead, tenant: tenant, name: "Silva, João; Jr", phone: "11999999999")

    expect(described_class.content(lead)).to include("FN:[Unitymob] Silva\\, João\\; Jr")
  end

  it "gera nome de arquivo seguro e transliterado" do
    lead = create(:lead, tenant: tenant, name: "João da Silva", phone: "11999999999")

    expect(described_class.filename(lead)).to eq("[Unitymob] Joao da Silva.vcf")
  end

  it "monta o cartão nativo da Cloud API" do
    lead = create(:lead, tenant: tenant, name: "João da Silva",
      phone: "5515997750237", email: "joao@example.com")

    card = described_class.card(lead)

    expect(card[:name]).to eq({ formatted_name: "[Unitymob] João da Silva", first_name: "João", last_name: "Silva" })
    expect(card[:phones]).to eq([{ phone: "+5515997750237", type: "CELL" }])
    expect(card[:emails]).to eq([{ email: "joao@example.com", type: "WORK" }])
    expect(card[:org]).to eq({ company: tenant.name })
  end
end

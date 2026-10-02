require "rails_helper"

RSpec.describe Portal::GrupozapLead do
  def payload(overrides = {})
    {
      "leadOrigin" => "Grupo OLX",
      "timestamp" => "2026-10-02T12:00:00.000Z",
      "originLeadId" => "lead-123",
      "originListingId" => "87027856",
      "clientListingId" => "AP-100",
      "name" => "Maria Silva",
      "email" => "maria@example.test",
      "ddd" => "47",
      "phone" => "999999999",
      "phoneNumber" => "47999999999",
      "message" => "Tenho interesse neste imóvel.",
      "temperature" => "Alta",
      "transactionType" => "SELL",
      "extraData" => { "leadType" => "CONTACT_CHAT" }
    }.merge(overrides)
  end

  it "normaliza lead completo" do
    lead = described_class.call(payload)

    expect(lead[:origin_lead_id]).to eq("lead-123")
    expect(lead[:listing_code]).to eq("AP-100")
    expect(lead[:name]).to eq("Maria Silva")
    expect(lead[:email]).to eq("maria@example.test")
    expect(lead[:phone]).to eq("5547999999999")
    expect(lead[:lead_type]).to eq("CONTACT_CHAT")
    expect(lead[:mcmv]).to be_nil
  end

  it "monta telefone de ddd + phone quando phoneNumber ausente" do
    lead = described_class.call(payload("phoneNumber" => nil))

    expect(lead[:phone]).to eq("5547999999999")
  end

  it "retorna nil sem originLeadId" do
    expect(described_class.call(payload("originLeadId" => "  "))).to be_nil
    expect(described_class.call({})).to be_nil
    expect(described_class.call(nil)).to be_nil
  end

  it "sinaliza MCMV sem anúncio" do
    lead = described_class.call(payload(
      "leadOrigin" => "MCMV_OLX",
      "originListingId" => nil,
      "clientListingId" => nil,
      "extraData" => { "mcmv" => { "sellerDocument" => "12345678000190" } }
    ))

    expect(lead[:listing_code]).to be_nil
    expect(lead[:mcmv]).to eq({ "sellerDocument" => "12345678000190" })
  end
end

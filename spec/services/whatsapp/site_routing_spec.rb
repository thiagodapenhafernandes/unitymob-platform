require "rails_helper"

RSpec.describe Whatsapp::SiteRouting do
  describe ".for_habitation" do
    before do
      described_class.update!(
        default_number: "47 3311-1067",
        rules: {
          "sale" => { "number" => "47 99999-0001", "capture_enabled" => "1" },
          "rent" => { "number" => "47 99999-0002", "capture_enabled" => "0" },
          "sale_rent" => { "number" => "47 99999-0003", "capture_enabled" => "1" }
        }
      )
    end

    it "routes sale properties to the sale number" do
      habitation = create(:habitation, valor_venda_cents: 500_000_00, valor_locacao_cents: 0)

      routing = described_class.for_habitation(habitation, message: "Quero comprar")

      expect(routing[:negotiation_type]).to eq("sale")
      expect(routing[:capture_required]).to be(true)
      expect(routing[:whatsapp_url]).to include("wa.me/5547999990001")
    end

    it "routes rent properties to the rent number without intermediate capture when disabled" do
      habitation = create(:habitation, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 8_000_00)

      routing = described_class.for_habitation(habitation, message: "Quero alugar")

      expect(routing[:negotiation_type]).to eq("rent")
      expect(routing[:capture_required]).to be(false)
      expect(routing[:whatsapp_url]).to include("wa.me/5547999990002")
    end

    it "routes sale and rent properties to the combined number" do
      habitation = create(:habitation, status: "Venda", valor_venda_cents: 500_000_00, valor_locacao_cents: 8_000_00)

      routing = described_class.for_habitation(habitation, message: "Quero detalhes")

      expect(routing[:negotiation_type]).to eq("sale_rent")
      expect(routing[:whatsapp_url]).to include("wa.me/5547999990003")
    end

    it "uses the editable default number when the specific rule has no number" do
      described_class.update!(
        default_number: "47 3333-4444",
        rules: {
          "sale" => { "number" => "", "capture_enabled" => "1" },
          "rent" => { "number" => "", "capture_enabled" => "1" },
          "sale_rent" => { "number" => "", "capture_enabled" => "1" }
        }
      )
      habitation = create(:habitation, valor_venda_cents: 500_000_00, valor_locacao_cents: 0)

      routing = described_class.for_habitation(habitation)

      expect(routing[:whatsapp_url]).to include("wa.me/554733334444")
    end
  end
end

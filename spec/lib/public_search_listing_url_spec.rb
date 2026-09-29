require "rails_helper"

RSpec.describe PublicSearch::ListingUrl do
  let(:tenant) { Tenant.default }

  before do
    create(:habitation, tenant:, categoria: "Apartamento")
      .tap { |habitation| habitation.address.update!(cidade: "Balneário Camboriú", bairro: "Centro") }
  end

  describe ".matches?" do
    it "captura URLs na gramática nova e ignora as legadas" do
      expect(described_class.matches?("/imoveis/venda/2-quartos")).to be(true)
      expect(described_class.matches?("/imoveis/venda/2-quartos+3-quartos/sacada+mobiliado")).to be(true)
      expect(described_class.matches?("/imoveis/venda/ate-500-mil")).to be(true)
      expect(described_class.matches?("/imoveis/venda/50-100m2")).to be(true)
      expect(described_class.matches?("/imoveis/venda/busca-yachthouse")).to be(true)
      expect(described_class.matches?("/imoveis/venda/apartamento/bc/x/y/z")).to be(true)
    end

    it "não rouba URLs legadas simples" do
      expect(described_class.matches?("/imoveis/venda")).to be(false)
      expect(described_class.matches?("/imoveis/venda/apartamento")).to be(false)
      expect(described_class.matches?("/imoveis/venda/apartamento/balneario-camboriu")).to be(false)
      expect(described_class.matches?("/imoveis")).to be(false)
      expect(described_class.matches?("/venda")).to be(false)
    end
  end

  describe ".build" do
    it "monta a URL completa do exemplo aprovado" do
      path = described_class.build(
        transaction_type: "venda",
        bedrooms: [2, 3],
        characteristics: %w[sacada mobiliado]
      )

      expect(path).to eq("/imoveis/venda/2-quartos+3-quartos/sacada+mobiliado")
    end

    it "monta faixas de área, preço e mínimos" do
      path = described_class.build(
        transaction_type: "venda",
        category: ["Apartamento"],
        city: ["Centro - Balneário Camboriú"],
        min_bedrooms: 4,
        min_area: 50,
        max_area: 100,
        min_price: 500_000,
        max_price: 1_000_000,
        search: "Yachthouse"
      )

      expect(path).to eq(
        "/imoveis/venda/apartamento/centro-balneario-camboriu" \
        "/4-mais-quartos/50-100m2/500-mil-1-milhao/busca-yachthouse"
      )
    end

    it "consome price_range do form da home sem vazar na query" do
      path = described_class.build(
        transaction_type: "venda",
        category: ["Apartamento"],
        price_range: "3200000-5800000"
      )

      expect(path).to eq("/imoveis/venda/apartamento/3200000-5800000")
    end

    it "formata valor quebrado acima de 1M em número cru exato" do
      path = described_class.build(transaction_type: "venda", min_price: 3_200_000, max_price: 5_800_000)

      expect(path).to eq("/imoveis/venda/3200000-5800000")

      parsed = described_class.new(tenant:).params_for("venda", "3200000-5800000")
      expect(parsed).to include(min_price: 3_200_000, max_price: 5_800_000)
    end

    it "normaliza contagens na regra das pills (1-3 exato, 4+ mínimo)" do
      expect(described_class.build(transaction_type: "venda", bedrooms: [5]))
        .to eq("/imoveis/venda/4-mais-quartos")
      expect(described_class.build(transaction_type: "venda", bedrooms: [2, 5]))
        .to eq("/imoveis/venda/4-mais-quartos")
      expect(described_class.build(transaction_type: "venda", bedrooms: [2], min_bedrooms: 4))
        .to eq("/imoveis/venda/4-mais-quartos")

      parsed = described_class.new(tenant:).params_for("venda", "5-quartos")
      expect(parsed).to include(min_bedrooms: 4)
      expect(parsed).not_to have_key(:bedrooms)
    end

    it "mínimo vence exatos no mesmo parse (evita AND impossível)" do
      parsed = described_class.new(tenant:).params_for("venda", "2-quartos+4-mais-quartos")

      expect(parsed).to include(min_bedrooms: 4)
      expect(parsed).not_to have_key(:bedrooms)
    end

    it "unifica flags avulsas no bloco de características" do
      path = described_class.build(
        transaction_type: "aluguel",
        furnished: "1",
        accepts_financing: true,
        max_price: 5_000
      )

      expect(path).to eq("/imoveis/aluguel/ate-5-mil/mobiliado+aceita-financiamento")
    end
  end

  describe "#params_for" do
    it "interpreta transação, categoria, local e características" do
      params = described_class.new(tenant:).params_for(
        "venda", "apartamento/centro-balneario-camboriu/frente-mar+mobiliado"
      )

      expect(params).to include(
        transaction_type: "venda",
        category: ["Apartamento"],
        city: ["Centro - Balneário Camboriú"],
        characteristics: %w[frente_mar mobiliado]
      )
    end

    it "interpreta contagens exatas, mínimas, área, preço e busca" do
      params = described_class.new(tenant:).params_for(
        "venda",
        "2-quartos+3-quartos/1-suite/2-vagas/4-mais-banheiros" \
        "/50-100m2/500-mil-1-milhao/busca-yachthouse"
      )

      expect(params).to include(
        bedrooms: [2, 3],
        suites: [1],
        parking: [2],
        min_bathrooms: 4,
        min_area: 50,
        max_area: 100,
        min_price: 500_000,
        max_price: 1_000_000,
        search: "yachthouse"
      )
    end

    it "ignora segmentos todos como o legado" do
      params = described_class.new(tenant:).params_for("venda", "todos/sacada")

      expect(params).to eq(transaction_type: "venda", characteristics: %w[sacada])
    end

    it "retorna nil para slug estrutural desconhecido" do
      expect(described_class.new(tenant:).params_for("venda", "busca-")).to be_nil
    end
  end

  describe "roundtrip" do
    it "reconstrói os mesmos filtros a partir da URL gerada" do
      filters = {
        transaction_type: "venda",
        category: ["Apartamento"],
        city: ["Centro - Balneário Camboriú"],
        bedrooms: [2, 3],
        min_area: 50,
        max_area: 100,
        min_price: 500_000,
        max_price: 1_000_000,
        characteristics: %w[sacada mobiliado]
      }

      path = described_class.build(filters)
      _empty, _imoveis, transaction, *segments = path.split("/")
      parsed = described_class.new(tenant:).params_for(transaction, segments.join("/"))

      expect(parsed).to include(
        transaction_type: "venda",
        category: ["Apartamento"],
        city: ["Centro - Balneário Camboriú"],
        bedrooms: [2, 3],
        min_area: 50,
        max_area: 100,
        min_price: 500_000,
        max_price: 1_000_000,
        characteristics: %w[sacada mobiliado]
      )
    end
  end
end

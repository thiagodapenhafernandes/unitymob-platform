require "rails_helper"

RSpec.describe Vista::PropertyReconciliationService do
  describe "bathroom mapping" do
    it "uses the Vista form bathroom count before the aggregated bathroom count" do
      service = described_class.new(codigos: ["8627"], dry_run: true)

      count = service.send(
        :bathrooms_count,
        {
          "BanheiroSocialQtd" => "4",
          "TotalBanheiros" => "7"
        }
      )

      expect(count).to eq(4)
    end

    it "falls back to the aggregated bathroom count when the form count is blank" do
      service = described_class.new(codigos: ["8627"], dry_run: true)

      count = service.send(
        :bathrooms_count,
        {
          "BanheiroSocialQtd" => "",
          "TotalBanheiros" => "7"
        }
      )

      expect(count).to eq(7)
    end
  end

  describe "rent total mapping" do
    it "does not use condominium and IPTU as rent total when base rent is zero" do
      service = described_class.new(codigos: ["8628"], dry_run: true)

      total = service.send(
        :total_rent_cents,
        {
          "ValorLocacao" => "0",
          "ValorCondominio" => "1400",
          "ValorIptu" => "334",
          "ValorTotalAluguel" => "1734"
        }
      )

      expect(total).to eq(0)
    end

    it "uses the base rent as normalized rent total when rent is present" do
      service = described_class.new(codigos: ["8573"], dry_run: true)

      total = service.send(
        :total_rent_cents,
        {
          "ValorLocacao" => "7500",
          "ValorCondominio" => "0",
          "ValorIptu" => "0",
          "ValorTotalAluguel" => "7500"
        }
      )

      expect(total).to eq(750_000)
    end
  end

  describe "development link mapping" do
    let(:service) { described_class.new(codigos: ["6173"], dry_run: true) }

    it "clears stale development code when Vista sends an empty development code" do
      attrs = service.send(
        :clearable_property_attrs,
        {
          "Codigo" => "6173",
          "CodigoEmpreendimento" => "",
          "Empreendimento" => "",
          "TituloSite" => ""
        }
      )

      expect(attrs[:codigo_empreendimento]).to be_nil
      expect(attrs[:nome_empreendimento]).to be_nil
      expect(attrs[:titulo_anuncio]).to be_nil
    end

    it "does not touch development code when Vista omits the development code field" do
      attrs = service.send(
        :clearable_property_attrs,
        {
          "Codigo" => "6173",
          "Empreendimento" => ""
        }
      )

      expect(attrs).not_to have_key(:codigo_empreendimento)
      expect(attrs[:nome_empreendimento]).to be_nil
    end
  end

  describe "publication flag preservation" do
    let(:service) { described_class.new(codigos: ["6173"], dry_run: true) }

    it "preserva a publicação local quando o imóvel já existe" do
      habitation = build_stubbed(:habitation, exibir_no_site_flag: false)

      flag = service.send(
        :local_publication_flag_for,
        habitation,
        {
          "ExibirNoSite" => "Sim",
          "ExibirNoSiteSalute" => "Sim"
        }
      )

      expect(flag).to be(false)
    end

    it "usa a API para definir a publicação inicial de imóvel novo" do
      habitation = build(:habitation, exibir_no_site_flag: false)

      flag = service.send(
        :local_publication_flag_for,
        habitation,
        {
          "ExibirNoSite" => "Sim",
          "ExibirNoSiteSalute" => "Nao"
        }
      )

      expect(flag).to be(true)
    end
  end

  describe "commission and rental management mapping" do
    let(:service) { described_class.new(codigos: ["8573"], dry_run: true) }

    it "uses the positive general commission percentage when the captador percentage is zero" do
      percentage = service.send(:commission_percentage, "0", "6")

      expect(percentage).to eq(BigDecimal("6"))
    end

    it "extracts the commission amount from Vista notes when the structured field is zero" do
      cents = service.send(
        :commission_amount_cents,
        {
          "ValorComissao" => "0",
          "ObsVenda" => "Tem Administração?  Sim\nValor da comissão: 7500"
        }
      )

      expect(cents).to eq(750_000)
    end

    it "uses Vista notes as a fallback for the Salute rental management flag" do
      flag = service.send(
        :rental_management_flag,
        {
          "ObsVenda" => "Método de garantia locação: Seguro Fiança\nTem Administração?  Sim"
        }
      )

      expect(flag).to be(true)
    end
  end
end

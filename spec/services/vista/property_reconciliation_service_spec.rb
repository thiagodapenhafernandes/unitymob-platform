require "rails_helper"

RSpec.describe Vista::PropertyReconciliationService do
  around do |example|
    previous_tenant = Current.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

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

  describe "tenant isolation" do
    it "resolve proprietario e corretor apenas no Tenant corrente" do
      current_tenant = Tenant.create!(name: "Tenant reconcile #{SecureRandom.hex(3)}", slug: "tenant-reconcile-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro reconcile #{SecureRandom.hex(3)}", slug: "outro-reconcile-#{SecureRandom.hex(3)}")
      current_profile = current_tenant.profiles.find_by!(key: "agent")
      other_profile = other_tenant.profiles.find_by!(key: "agent")
      current_broker = create(:admin_user, tenant: current_tenant, profile: current_profile, vista_id: "BROKER-REC-1")
      create(:admin_user, tenant: other_tenant, profile: other_profile, vista_id: "BROKER-REC-2")
      other_proprietor = create(:proprietor, tenant: other_tenant, vista_code: "PROP-REC-1", name: "Proprietário Externo")

      Current.tenant = current_tenant
      service = described_class.new(codigos: ["REC-1"], dry_run: true)

      expect(service.send(:resolve_broker, { "CodigoCorretor" => "BROKER-REC-1" })).to eq(current_broker)
      expect(service.send(:resolve_broker, { "CodigoCorretor" => "BROKER-REC-2" })).to be_nil

      proprietor = service.send(:resolve_proprietor, { "CodigoProprietario" => "PROP-REC-1", "Proprietario" => "Proprietário Atual" })
      expect(proprietor.tenant).to eq(current_tenant)
      expect(proprietor.id).not_to eq(other_proprietor.id)
    end

    it "valida duplicidade de codigo DWV apenas dentro do Tenant corrente" do
      current_tenant = Tenant.create!(name: "Tenant dwv #{SecureRandom.hex(3)}", slug: "tenant-dwv-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro dwv #{SecureRandom.hex(3)}", slug: "outro-dwv-#{SecureRandom.hex(3)}")
      create(:habitation, tenant: other_tenant, codigo: "OUT-DWV", codigo_dwv: "DWV-1")
      habitation = build(:habitation, tenant: current_tenant, codigo: "CUR-DWV")

      Current.tenant = current_tenant
      service = described_class.new(codigos: ["CUR-DWV"], dry_run: true)

      expect(service.send(:unique_dwv_code, { "CodigoDWV" => "DWV-1" }, habitation)).to eq("DWV-1")
    end
  end
end

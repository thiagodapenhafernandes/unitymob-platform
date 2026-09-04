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

  describe "inactive commercial status mapping" do
    let(:service) { described_class.new(codigos: ["1013"], dry_run: true) }

    it "maps Vista sale value as the required sold value" do
      attrs = service.send(
        :inactive_commercial_value_attrs,
        "Vendido terceiros",
        { "ValorVenda" => "980000" }
      )

      expect(attrs).to eq(valor_vendido_terceiros_cents: 98_000_000)
    end

    it "maps Vista rental value as the required rented value" do
      attrs = service.send(
        :inactive_commercial_value_attrs,
        "Alugado terceiros",
        { "ValorLocacao" => "4500", "ValorCondominio" => "800" }
      )

      expect(attrs).to eq(valor_alugado_terceiros_cents: 450_000)
    end

    it "maps Vista status as the required suspension reason" do
      attrs = service.send(
        :inactive_commercial_value_attrs,
        "Suspenso",
        { "Status" => "Suspenso", "Situacao" => "" }
      )

      expect(attrs).to eq(motivo_suspensao: "Suspenso")
    end
  end

  describe "association sync flags" do
    it "can skip documents and prontuarios for faster property/photo migrations" do
      service = described_class.new(
        codigos: ["1013"],
        dry_run: true,
        sync_documents: false,
        sync_prontuarios: false
      )

      associations = service.send(:association_fields_for_sync).keys

      expect(associations).to include("proprietarios", "FotoEmpreendimento", "Video")
      expect(associations).not_to include("Anexo", "prontuarios")
    end
  end

  describe "attribute option upsert" do
    it "treats duplicate option validation as idempotent" do
      tenant = Tenant.create!(name: "Tenant options #{SecureRandom.hex(3)}", slug: "tenant-options-#{SecureRandom.hex(3)}")
      Current.tenant = tenant
      service = described_class.new(codigos: ["1862"], dry_run: true)
      duplicate = AttributeOption.new(tenant: tenant, context: "habitation", category: "feature", name: "Portaria24 Hrs")
      duplicate.errors.add(:name, "já existe nesta categoria")
      allow(tenant.attribute_options).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(duplicate))

      expect {
        service.send(:ensure_attribute_options!, ["Portaria24 Hrs"], [])
      }.not_to raise_error
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

    it "preserves Vista development name for apartments even without a development code" do
      attrs = service.send(
        :clearable_property_attrs,
        {
          "Codigo" => "3186",
          "Categoria" => "Apartamento",
          "CodigoEmpreendimento" => "",
          "Empreendimento" => "Edifício Dom Gabriel"
        }
      )

      expect(attrs[:codigo_empreendimento]).to be_nil
      expect(attrs[:nome_empreendimento]).to eq("Edifício Dom Gabriel")
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
      broker_by_name = create(:admin_user, tenant: current_tenant, profile: current_profile, name: "Fabíana Albuquerque", vista_id: nil)
      create(:admin_user, tenant: other_tenant, profile: other_profile, vista_id: "BROKER-REC-2")
      other_proprietor = create(:proprietor, tenant: other_tenant, vista_code: "PROP-REC-1", name: "Proprietário Externo")

      Current.tenant = current_tenant
      service = described_class.new(codigos: ["REC-1"], dry_run: true)

      expect(service.send(:resolve_broker, { "CodigoCorretor" => "BROKER-REC-1" })).to eq(current_broker)
      expect(service.send(:resolve_broker, { "CodigoCorretor" => "BROKER-REC-2" })).to be_nil
      expect(service.send(:resolve_broker, { "Corretor" => "Fabiana Albuquerque" })).to eq(broker_by_name)

      proprietor = service.send(:resolve_proprietor, { "CodigoProprietario" => "PROP-REC-1", "Proprietario" => "Proprietário Atual" })
      expect(proprietor.tenant).to eq(current_tenant)
      expect(proprietor.id).not_to eq(other_proprietor.id)
    end

    it "clears all-zero Vista complements instead of showing apartment 0000" do
      service = described_class.new(codigos: ["6425"], dry_run: true)

      expect(service.send(:clearable_property_attrs, { "Complemento" => "0000" })[:complemento]).to be_nil
      expect(service.send(:clearable_address_attrs, { "Complemento" => "2901" })[:complemento]).to eq("2901")
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

  describe "owner phone reconciliation" do
    it "espelha o telefone principal da Vista nos campos legados do imóvel" do
      tenant = Tenant.create!(name: "Tenant owner phones #{SecureRandom.hex(3)}", slug: "tenant-owner-phones-#{SecureRandom.hex(3)}")
      Current.tenant = tenant
      habitation = create(:habitation, tenant: tenant, codigo: "7110", proprietario_celular: nil)
      service = described_class.new(codigos: ["7110"], dry_run: true)
      api = {
        "Codigo" => "7110",
        "CodigoProprietario" => "28615",
        "Proprietario" => "Eliseu",
        "proprietarios" => {
          "28615" => {
            "Codigo" => "28615",
            "Nome" => "Eliseu",
            "Celular" => "",
            "FonePrincipal" => "41 98428.2142",
            "FoneComercial" => "",
            "FoneResidencial" => ""
          }
        }
      }

      owner = service.send(:resolve_proprietor, api)
      service.send(:update_property!, habitation, api, owner, nil, [], [])

      expect(habitation.reload.proprietario_celular).to eq("5541984282142")
      expect(habitation.proprietario_telefone).to eq("5541984282142")
    end
  end

  describe "Vista API requests" do
    it "usa timeouts explicitos nas consultas de detalhes" do
      service = described_class.new(codigos: ["7110"], dry_run: true)

      expect(HTTParty).to receive(:get).with(
        a_string_ending_with("/imoveis/detalhes"),
        hash_including(
          query: hash_including(imovel: "7110"),
          headers: hash_including("Accept" => "application/json"),
          open_timeout: 10,
          timeout: 30
        )
      ).and_return(double(code: 200, body: { "Codigo" => "7110" }.to_json))

      expect(service.send(:fetch_detail, "7110", ["Codigo"])).to eq("Codigo" => "7110")
    end

    it "permite forcar o header Host quando a execucao aponta para um IP especifico" do
      previous_host_header = ENV["VISTA_HOST_HEADER"]
      ENV["VISTA_HOST_HEADER"] = "saluteim20174-rest.vistahost.com.br"
      service = described_class.new(codigos: ["7110"], dry_run: true, host: "http://100.55.193.123")

      expect(HTTParty).to receive(:get).with(
        "http://100.55.193.123/imoveis/detalhes",
        hash_including(
          headers: hash_including("Host" => "saluteim20174-rest.vistahost.com.br")
        )
      ).and_return(double(code: 200, body: { "Codigo" => "7110" }.to_json))

      expect(service.send(:fetch_detail, "7110", ["Codigo"])).to eq("Codigo" => "7110")
    ensure
      ENV["VISTA_HOST_HEADER"] = previous_host_header
    end
  end
end

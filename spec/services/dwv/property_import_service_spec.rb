require "rails_helper"

RSpec.describe Dwv::PropertyImportService do
  let(:tenant) { Tenant.default }

  describe "#perform" do
    it "creates a DWV habitation with the full unit/building mapping" do
      dwv_user = create(:admin_user, tenant: tenant, name: "Dwv - Imóveis Pauta", email: "laudicardoso@gmail.com")
      create(:habitation, tenant: tenant, codigo: "8628", imovel_dwv: "Nao", last_sync_message: "Importado do dump Vista")

      result = described_class.new(unit_payload, tenant: tenant).perform

      habitation = result[:habitation]
      expect(habitation).to be_persisted
      expect(habitation.codigo).to eq("8629")
      expect(habitation.codigo_dwv).to eq("632439")
      expect(habitation.imovel_dwv).to eq("Sim")
      expect(habitation.admin_user).to eq(dwv_user)
      expect(habitation.status).to eq("Venda")
      expect(habitation.titulo_anuncio).to eq("Apartamento com vista mar")
      expect(habitation.nome_empreendimento).to eq("Línea")
      expect(habitation.codigo_empreendimento).to be_nil
      expect(habitation.categoria).to eq("Apartamento")
      expect(habitation.situacao).to eq("Construção")
      expect(habitation.area_privativa_m2).to eq(BigDecimal("186.0"))
      expect(habitation.area_util_m2).to eq(BigDecimal("186.0"))
      expect(habitation.valor_venda_cents).to eq(439_776_500)
      expect(habitation.dormitorios_qtd).to eq(4)
      expect(habitation.suites_qtd).to eq(4)
      expect(habitation.banheiros_qtd).to eq(5)
      expect(habitation.vagas_qtd).to eq(3)
      expect(habitation.descricao_web.to_plain_text).to include("Descrição completa do imóvel")
      expect(habitation.descricao_empreendimento).to eq("Empreendimento com lazer completo.")
      expect(habitation.infra_estrutura).to include("Piscina")
      expect(habitation.caracteristicas.values).to include("Frente mar", "Sacada com churrasqueira")
      expect(habitation.pictures.map { |pic| pic["url"] }).to include("https://cdn.dwv.test/unit-cover.jpg")
      expect(habitation.fotos_empreendimento.map { |pic| pic["url"] }).to include("https://cdn.dwv.test/building-cover.jpg")
      expect(habitation.videos.map { |video| video["url"] }).to include("https://cdn.dwv.test/video.mp4")
      expect(habitation.plantas.map { |planta| planta["url"] }).to include("https://cdn.dwv.test/planta.jpg")
      expect(habitation.tour_virtual).to eq("https://tour.dwv.test/linea")
      expect(habitation.condicoes_negociacao).to include("Entrada: 1000000.00")
      expect(habitation.constructor.name).to eq("Rzilli")
      expect(habitation.dwv_payload).to include("id" => 632439)

      address = habitation.address
      expect(address.logradouro).to eq("Rua 2450")
      expect(address.numero).to eq("60")
      expect(address.bairro).to eq("Centro")
      expect(address.cidade).to eq("Balneário Camboriú")
      expect(address.uf).to eq("SC")
      expect(address.cep).to eq("88330-410")
      expect(address.imediacoes).to eq(["A 30m da Av. Brasil"])
    end

    it "updates rich fields on an existing DWV record" do
      habitation = create(
        :habitation,
        tenant: tenant,
        codigo: "DWV-632439",
        codigo_dwv: "632439",
        imovel_dwv: "Sim",
        titulo_anuncio: "Título antigo",
        descricao_web: nil,
        pictures: [],
        area_privativa_m2: nil
      )

      described_class.new(unit_payload, tenant: tenant).perform
      habitation.reload

      expect(habitation.titulo_anuncio).to eq("Apartamento com vista mar")
      expect(habitation.descricao_web.to_plain_text).to include("Descrição completa do imóvel")
      expect(habitation.area_privativa_m2).to eq(BigDecimal("186.0"))
      expect(habitation.pictures.map { |pic| pic["url"] }).to include("https://cdn.dwv.test/unit-cover.jpg")
      expect(habitation.address.logradouro).to eq("Rua 2450")
      expect(habitation.last_sync_message).to eq("Sincronizado via DWV (mapeamento completo)")
    end

    it "não atualiza imóvel DWV de outro tenant com o mesmo código externo" do
      current_tenant = Tenant.create!(name: "Tenant DWV #{SecureRandom.hex(3)}", slug: "tenant-dwv-import-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro DWV #{SecureRandom.hex(3)}", slug: "outro-dwv-import-#{SecureRandom.hex(3)}")
      other_habitation = create(
        :habitation,
        tenant: other_tenant,
        codigo: "OUT-DWV-632439",
        codigo_dwv: "632439",
        imovel_dwv: "Sim",
        titulo_anuncio: "Título do outro tenant"
      )

      result = described_class.new(unit_payload, tenant: current_tenant).perform

      expect(result[:habitation]).to be_persisted
      expect(result[:habitation].tenant).to eq(current_tenant)
      expect(result[:habitation].codigo_dwv).to eq("632439")
      expect(result[:habitation].titulo_anuncio).to eq("Apartamento com vista mar")
      expect(other_habitation.reload).to have_attributes(
        tenant_id: other_tenant.id,
        titulo_anuncio: "Título do outro tenant",
        codigo_dwv: "632439"
      )
    end

    it "maps third party property fields without requiring unit data" do
      result = described_class.new(third_party_payload, tenant: tenant).perform
      habitation = result[:habitation]

      expect(habitation.status).to eq("Aluguel")
      expect(habitation.categoria).to eq("Casa")
      expect(habitation.valor_locacao_cents).to eq(12_000_00)
      expect(habitation.valor_condominio_cents).to eq(450_00)
      expect(habitation.valor_iptu_cents).to eq(180_00)
      expect(habitation.area_privativa_m2).to eq(BigDecimal("220.0"))
      expect(habitation.dormitorios_qtd).to eq(3)
      expect(habitation.pictures.map { |pic| pic["url"] }).to include("https://cdn.dwv.test/casa.jpg")
      expect(habitation.address.logradouro).to eq("Rua 1000")
      expect(habitation.address.numero).to eq("55")
      expect(habitation.address.complemento).to eq("Casa 2")
    end

    it "promotes a residence name stuck in the address complement to nome_empreendimento" do
      payload = third_party_payload.deep_dup
      payload["data"]["third_party_property"]["address"]["complement"] = "BOULEVARD DA BARRA PARK RESIDENCE"
      payload["data"]["third_party_property"].delete("unit_info")

      result = described_class.new(payload, tenant: tenant).perform
      habitation = result[:habitation]

      # casa com nome de residencial no complemento => Casa em Condomínio, para o
      # nome persistir (categoria standalone zeraria nome_empreendimento).
      expect(habitation.categoria).to eq("Casa em Condomínio")
      expect(habitation.nome_empreendimento).to eq("BOULEVARD DA BARRA PARK RESIDENCE")
      # o complemento era, na íntegra, o nome do empreendimento: sai do endereço
      expect(habitation.address.complemento).to be_blank
      expect(habitation.bloco).to be_blank
    end

    it "keeps a real unit complement in the address and out of nome_empreendimento" do
      payload = third_party_payload.deep_dup
      payload["data"]["third_party_property"]["address"]["complement"] = "Casa 2"
      payload["data"]["third_party_property"].delete("unit_info")

      result = described_class.new(payload, tenant: tenant).perform
      habitation = result[:habitation]

      expect(habitation.nome_empreendimento).to be_blank
      expect(habitation.address.complemento).to eq("Casa 2")
    end

    it "classifies third party house in gated condominium from DWV unit info" do
      payload = third_party_payload.deep_dup
      payload["data"]["third_party_property"].merge!(
        "title" => "Casa Condomínio Bosque de Taquaras",
        "type" => "Casa",
        "unit_info" => "Condomínio Fechado"
      )

      result = described_class.new(payload, tenant: tenant).perform
      habitation = result[:habitation]

      expect(habitation.categoria).to eq("Casa em Condomínio")
      expect(habitation.nome_empreendimento).to eq("Condomínio Bosque de Taquaras")
      expect(habitation.address.complemento).to eq("Condomínio Fechado")
    end
  end

  def unit_payload
    {
      "data" => {
        "id" => 632439,
        "status" => "active",
        "deleted" => false,
        "title" => "Apartamento com vista mar",
        "advertisement_title" => "Apartamento com vista mar",
        "description_text" => "Descrição completa do imóvel.",
        "construction_stage_raw" => "under construction",
        "inserted_at" => "2026-01-10T10:00:00-03:00",
        "last_updated_at" => "2026-06-08T14:15:00-03:00",
        "unit" => {
          "title" => "901",
          "type" => "Apartamento",
          "price" => "4397765.00",
          "private_area" => "186.0",
          "util_area" => "186.0",
          "total_area" => "0.0",
          "dorms" => 4,
          "suites" => 4,
          "bathroom" => 5,
          "parking_spaces" => 3,
          "cover" => { "url" => "https://cdn.dwv.test/unit-cover.jpg" },
          "payment_conditions" => [
            { "name" => "Entrada", "price" => "1000000.00" }
          ],
          "floor_plan" => {
            "category" => { "title" => "Apartamento", "tag" => "Residencial" },
            "images" => [{ "url" => "https://cdn.dwv.test/planta.jpg" }]
          }
        },
        "building" => {
          "id" => 9001,
          "title" => "Línea",
          "description" => "<p>Empreendimento com lazer completo.</p>",
          "delivery_date" => "2029-06-01",
          "cover" => { "url" => "https://cdn.dwv.test/building-cover.jpg" },
          "gallery" => [{ "url" => "https://cdn.dwv.test/building-gallery.jpg" }],
          "videos" => [{ "url" => "https://cdn.dwv.test/video.mp4" }],
          "virtual_tour" => "https://tour.dwv.test/linea",
          "features" => [
            { "title" => "Piscina", "type" => "Empreendimento" },
            { "title" => "Frente Mar", "type" => "Apartamento" },
            { "title" => "Sacada com churrasqueira", "type" => "Apartamento" }
          ],
          "address" => {
            "street_name" => "Rua 2450",
            "street_number" => "60",
            "neighborhood" => "Centro",
            "city" => "Balneário Camboriú",
            "state" => "SC",
            "zip_code" => "88330-410",
            "country" => "Brasil",
            "complement" => "A 30m da Av. Brasil",
            "latitude" => "-26.9900000",
            "longitude" => "-48.6300000"
          }
        },
        "construction_company" => {
          "title" => "Rzilli",
          "site" => "https://rzilli.test"
        }
      }
    }
  end

  def third_party_payload
    {
      "data" => {
        "id" => 620000,
        "status" => "active",
        "deleted" => false,
        "third_party_property" => {
          "title" => "Casa para locação",
          "type" => "Casa",
          "rent" => "12000.00",
          "property_tax" => "180.00",
          "administration_fee" => "450.00",
          "private_area" => "220.0",
          "dorms" => 3,
          "suites" => 1,
          "bathroom" => 2,
          "parking_spaces" => 2,
          "unit_info" => "Casa 2",
          "cover" => { "url" => "https://cdn.dwv.test/casa.jpg" },
          "address" => {
            "street_name" => "Rua 1000",
            "street_number" => "55",
            "neighborhood" => "Centro",
            "city" => "Itapema",
            "state" => "SC",
            "zip_code" => "88220-000"
          }
        }
      }
    }
  end
end

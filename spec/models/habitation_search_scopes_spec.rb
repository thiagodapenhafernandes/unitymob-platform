require "rails_helper"

RSpec.describe Habitation::SearchScopes, type: :model do
  describe ".public_property_types" do
    it "includes fixed public type options even without published records" do
      expect(Habitation.public_property_types).to include("Diferenciado", "Garden")
    end
  end

  describe ".public_location_options" do
    it "deduplicates city and neighborhood options ignoring accents and casing" do
      first = create(:habitation, cidade: nil, bairro: nil)
      first.create_address!(
        logradouro: "Rua 1000",
        numero: "10",
        bairro: "Centro",
        cidade: "Balneário Camboriú",
        uf: "SC"
      )
      second = create(:habitation, cidade: nil, bairro: nil)
      second.create_address!(
        logradouro: "Rua 1100",
        numero: "20",
        bairro: "centro",
        cidade: "Balneario Camboriu",
        uf: "SC"
      )

      options = Habitation.public_location_options
      city_keys = options.select { |item| item[:type] == "city" }.map { |item| Habitation.normalize_location_value(item[:value]) }
      neighborhood_keys = options.select { |item| item[:type] == "neighborhood" }.map { |item| Habitation.normalize_location_value(item[:value]) }

      expect(city_keys.count("balneario camboriu")).to eq(1)
      expect(neighborhood_keys.count("centro - balneario camboriu")).to eq(1)
    end

    it "normalizes city and neighborhood labels to pt-BR title case" do
      habitation = create(:habitation, cidade: nil, bairro: nil)
      habitation.create_address!(
        logradouro: "Rua 1200",
        numero: "30",
        bairro: "praia brava de itajaí",
        cidade: "BALNEÁRIO CAMBORIÚ",
        uf: "SC"
      )

      options = Habitation.public_location_options

      expect(options).to include(hash_including(type: "city", label: "Balneário Camboriú"))
      expect(options).to include(hash_including(type: "neighborhood", label: "Praia Brava de Itajaí - Balneário Camboriú"))
    end

    it "uses lightweight public listing filters without requiring photo checks" do
      visible_without_photo = create(
        :habitation,
        cidade: "Cidade Sem Foto",
        bairro: "Centro",
        pictures: []
      )
      without_price = create(
        :habitation,
        cidade: "Cidade Sem Preço",
        bairro: "Centro",
        valor_venda_cents: 0,
        valor_locacao_cents: 0
      )
      dwv = create(
        :habitation,
        cidade: "Cidade DWV",
        bairro: "Centro",
        imovel_dwv: "Sim"
      )
      unavailable = create(
        :habitation,
        :unavailable,
        cidade: "Cidade Indisponível",
        bairro: "Centro"
      )

      [
        [visible_without_photo, "Cidade Sem Foto"],
        [without_price, "Cidade Sem Preço"],
        [dwv, "Cidade DWV"],
        [unavailable, "Cidade Indisponível"]
      ].each do |habitation, city|
        habitation.address.update!(cidade: city, bairro: "Centro")
      end

      options = Habitation.public_location_options
      city_labels = options.select { |item| item[:type] == "city" }.map { |item| item[:label] }

      expect(city_labels).to include("Cidade Sem Foto")
      expect(city_labels).not_to include("Cidade Sem Preço")
      expect(city_labels).not_to include("Cidade DWV")
      expect(city_labels).not_to include("Cidade Indisponível")
    end
  end

  describe "price sorting" do
    it "sorts by the available non-zero public price and keeps empty prices last" do
      rent = create(:habitation, codigo: "PRICE-RENT", valor_venda_cents: 0, valor_locacao_cents: 3_000_00)
      sale = create(:habitation, codigo: "PRICE-SALE", valor_venda_cents: 900_000_00, valor_locacao_cents: 0)
      empty = create(:habitation, codigo: "PRICE-EMPTY", valor_venda_cents: 0, valor_locacao_cents: 0)

      expect(Habitation.where(id: [rent.id, sale.id, empty.id]).price_asc.to_a).to eq([rent, sale, empty])
      expect(Habitation.where(id: [rent.id, sale.id, empty.id]).price_desc.to_a).to eq([sale, rent, empty])
    end
  end

  describe ".with_photos" do
    it "does not treat development photos as public photos for regular units" do
      unit_without_public_photo = create(
        :habitation,
        tipo: "Unitário",
        pictures: [],
        fotos_empreendimento: [{ "url" => "https://example.com/development.jpg" }]
      )

      result = Habitation.with_photos

      expect(result).not_to include(unit_without_public_photo)
    end

    it "does not include unit development payload photos unless the fallback is enabled" do
      development = create(:habitation, codigo: "DEV-PAYLOAD", tipo: "Empreendimento")
      unit = create(
        :habitation,
        tipo: "Unitário",
        codigo_empreendimento: development.codigo,
        pictures: [],
        fotos_empreendimento: [{ "url" => "https://example.com/development-payload.jpg" }],
        use_development_photos_flag: false
      )

      expect(Habitation.with_photos).not_to include(unit)
    end

    it "includes unit development payload photos when the fallback is enabled" do
      development = create(:habitation, codigo: "DEV-PAYLOAD-FALLBACK", tipo: "Empreendimento")
      unit = create(
        :habitation,
        tipo: "Unitário",
        codigo_empreendimento: development.codigo,
        pictures: [],
        fotos_empreendimento: [{ "url" => "https://example.com/development-payload.jpg" }],
        use_development_photos_flag: true
      )

      expect(Habitation.with_photos).to include(unit)
    end

    it "allows development photos for developments" do
      development = create(
        :habitation,
        tipo: "Empreendimento",
        pictures: [],
        fotos_empreendimento: [{ "url" => "https://example.com/development.jpg" }]
      )

      expect(Habitation.with_photos).to include(development)
    end

    it "does not include units from linked development photos unless the fallback is enabled" do
      development = create(
        :habitation,
        codigo: "DEV-WITH-PHOTO",
        tipo: "Empreendimento",
        pictures: [{ "url" => "https://example.com/development.jpg" }]
      )
      unit = create(
        :habitation,
        codigo: "UNIT-NO-FALLBACK",
        codigo_empreendimento: development.codigo,
        pictures: [],
        fotos_empreendimento: [],
        use_development_photos_flag: false
      )

      expect(Habitation.with_photos).not_to include(unit)
    end

    it "includes units from linked development photos when the fallback is enabled" do
      development = create(
        :habitation,
        codigo: "DEV-FALLBACK-PHOTO",
        tipo: "Empreendimento",
        pictures: [{ "url" => "https://example.com/development.jpg" }]
      )
      unit = create(
        :habitation,
        codigo: "UNIT-FALLBACK",
        codigo_empreendimento: development.codigo,
        pictures: [],
        fotos_empreendimento: [],
        use_development_photos_flag: true
      )

      expect(Habitation.with_photos).to include(unit)
    end
  end

  describe ".admin_search_text" do
    it "matches developments and linked units by development name without accents or exact casing" do
      development = create(
        :habitation,
        tipo: "Empreendimento",
        codigo: "DEV-LABELLE",
        nome_empreendimento: "La Belle Tour Résidence",
        titulo_anuncio: "Lançamento no Centro"
      )
      unit = create(
        :habitation,
        codigo: "UNIT-LABELLE",
        codigo_empreendimento: development.codigo,
        nome_empreendimento: nil,
        titulo_anuncio: "Apartamento 2 suítes"
      )
      other = create(:habitation, codigo: "OTHER-RESIDENCE", nome_empreendimento: "Outro Residencial")

      result = Habitation.admin_search_text("belle la")

      expect(result).to include(development, unit)
      expect(result).not_to include(other)
    end

    it "matches address fields by street, number, zip code and neighborhood" do
      matching = create(:habitation, codigo: "ADDR-MATCH", endereco: nil, numero: nil, cep: nil, bairro: nil)
      Address.create!(
        addressable: matching,
        tipo_endereco: "Rua",
        logradouro: "2000",
        numero: "120",
        bairro: "Centro",
        cidade: "Balneário Camboriú",
        uf: "SC",
        cep: "88330-590"
      )
      other = create(:habitation, codigo: "ADDR-OTHER", endereco: "Rua 1000", numero: "80", cep: "88330-000", bairro: "Barra Sul")

      result = Habitation.admin_search_text("rua 2000 120 88330-590 centro")

      expect(result).to include(matching)
      expect(result).not_to include(other)
    end
  end

  describe ".dependencia_empregada" do
    it "matches Vista characteristics for dependencia de empregada" do
      matching = create(:habitation, caracteristicas: ["Dependência de Empregada"])
      create(:habitation, caracteristicas: ["Lavabo"])

      expect(Habitation.dependencia_empregada).to contain_exactly(matching)
    end
  end

  describe ".advanced_search" do
    it "filters by dependencia de empregada characteristic" do
      matching = create(:habitation, caracteristicas: ["Dep. Empregada"])
      non_matching = create(:habitation, caracteristicas: ["Lavanderia"])

      result = Habitation.advanced_search(characteristics: ["dependencia_empregada"])

      expect(result).to include(matching)
      expect(result).not_to include(non_matching)
    end

    it "filters by gourmet kitchen with barbecue" do
      matching = create(:habitation, caracteristicas: ["Cozinha Gourmet"], infra_estrutura: ["Churrasqueira"])
      non_matching = create(:habitation, caracteristicas: ["Cozinha Planejada"], infra_estrutura: ["Piscina"])

      result = Habitation.advanced_search(characteristics: ["cozinha_gourmet_churrasqueira"])

      expect(result).to include(matching)
      expect(result).not_to include(non_matching)
    end

    it "filters by morning sun using face" do
      matching = create(:habitation, face: "Leste")
      non_matching = create(:habitation, face: "Oeste")

      result = Habitation.advanced_search(characteristics: ["sol_manha"])

      expect(result).to include(matching)
      expect(result).not_to include(non_matching)
    end

    it "filters by afternoon sun using face" do
      matching = create(:habitation, face: "Oeste")
      non_matching = create(:habitation, face: "Leste")

      result = Habitation.advanced_search(characteristics: ["sol_tarde"])

      expect(result).to include(matching)
      expect(result).not_to include(non_matching)
    end

    it "filters by all day sun using face" do
      matching = create(:habitation, face: "Norte")
      non_matching = create(:habitation, face: "Sul")

      result = Habitation.advanced_search(characteristics: ["sol_dia_todo"])

      expect(result).to include(matching)
      expect(result).not_to include(non_matching)
    end

    it "keeps filtering regular public types by category" do
      matching = create(:habitation, categoria: "Apartamento")
      non_matching = create(:habitation, categoria: "Casa")

      result = Habitation.advanced_search(category: ["Apartamento"])

      expect(result).to include(matching)
      expect(result).not_to include(non_matching)
    end

    it "filters Garden selected as a public type by the garden flag" do
      matching = create(:habitation, garden_flag: true, categoria: "Apartamento")
      non_matching = create(:habitation, garden_flag: false, categoria: "Apartamento")

      result = Habitation.advanced_search(category: ["Garden"])

      expect(result).to include(matching)
      expect(result).not_to include(non_matching)
    end

    it "filters Diferenciado selected as a public type by its unique feature" do
      matching = create(:habitation, caracteristica_unica: ["Diferenciado"], categoria: "Apartamento")
      non_matching = create(:habitation, caracteristica_unica: ["Decorado"], categoria: "Apartamento")

      result = Habitation.advanced_search(category: ["Diferenciado"])

      expect(result).to include(matching)
      expect(result).not_to include(non_matching)
    end

    it "filters sale minimum price without sending infinity to PostgreSQL" do
      relation = Habitation.advanced_search(transaction_type: "venda", min_price: "10000000")

      expect(relation.to_sql).to include("valor_venda_cents >= 1000000000")
      expect(relation.to_sql).not_to include("Infinity")
      expect { relation.count }.not_to raise_error
    end

    it "filters rent minimum price without sending infinity to PostgreSQL" do
      relation = Habitation.advanced_search(transaction_type: "aluguel", min_price: "10000")

      expect(relation.to_sql).to include("valor_locacao_cents >= 1000000")
      expect(relation.to_sql).not_to include("Infinity")
      expect { relation.count }.not_to raise_error
    end
  end
end

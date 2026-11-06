require "rails_helper"

RSpec.describe Instagram::CatalogReply do
  it "limita as recomendações a imóveis publicados pela conta do lead" do
    lead = create(:lead)
    tenant = lead.tenant
    public_property = create(:habitation, tenant: tenant, titulo_anuncio: "Imóvel publicado")
    private_property = create(:habitation, :unavailable, tenant: tenant, titulo_anuncio: "Imóvel privado")
    other_property = create(:habitation, tenant: Tenant.create!(name: "Outra imobiliária", slug: "outra-imobiliaria"), titulo_anuncio: "Imóvel de outra conta")
    allow(tenant).to receive(:public_base_url).and_return("https://catalogo.example")
    allow(Storage::PublicCdnImageUrl).to receive(:resolve).and_call_original
    allow(Storage::PublicCdnImageUrl).to receive(:resolve).with(public_property.public_image_sources.first)
      .and_return("https://catalogo.example/spec/property.jpg")
    query = instance_double(Ai::PropertySearch::PublicQuery, call: Ai::PropertySearch::PublicQuery::Result.new({}, nil, nil))
    allow(Ai::PropertySearch::PublicQuery).to receive(:new).with(tenant: tenant, text: "Quero uma casa").and_return(query)

    result = described_class.new(lead, { "property_code" => other_property.codigo }).call([{ role: "cliente", text: "Quero uma casa" }], first_turn: true)

    expect(result.body).to include(public_property.titulo_anuncio, "https://catalogo.example/imoveis/")
    expect(result.cards).to contain_exactly(hash_including(
      image_url: a_string_including("/spec/property.jpg"),
      buttons: [hash_including(title: "Ver imóvel", url: a_string_starting_with("https://catalogo.example/imoveis/"))]
    ))
    expect(result.body).not_to include(private_property.titulo_anuncio, other_property.titulo_anuncio, "Rua 1000")
  end
  describe "busca por Rua 3600" do
    let(:lead) { create(:lead) }
    let(:tenant) { lead.tenant }
    let(:messages) do
      [{ role: "cliente", text: "Quero apartamento com 3 quartos em balneário camboriú rua 3600 " }]
    end

    before do
      allow(tenant).to receive(:public_base_url).and_return("https://catalogo.example")
      filters = { "category" => ["Apartamento"], "min_bedrooms" => "3", "city" => ["Balneário Camboriú"] }
      query = instance_double(Ai::PropertySearch::PublicQuery, call: Ai::PropertySearch::PublicQuery::Result.new(filters, nil, nil))
      allow(Ai::PropertySearch::PublicQuery).to receive(:new)
        .with(tenant: tenant, text: "Quero apartamento com 3 quartos em balneário camboriú").and_return(query)
      allow(Storage::PublicCdnImageUrl).to receive(:resolve).and_return("https://catalogo.example/spec/property.jpg")
    end

    def apartment(street, title, bedrooms: 3)
      property = build(:habitation, tenant: tenant, categoria: "Apartamento", dormitorios_qtd: bedrooms, titulo_anuncio: title)
      property.address.logradouro = street
      property.save!
      property
    end

    it "entrega até três cartões da rua e preserva os outros critérios" do
      4.times { |index| apartment(index.even? ? "3600" : "Rua 3600", "Opção da rua #{index}") }
      apartment("Rua 36000", "Outra rua")
      apartment("Rua 3600", "Dois quartos", bedrooms: 2)

      result = described_class.new(lead, {}).call(messages, first_turn: true)

      expect(result.cards.size).to eq(3)
      expect(result.cards.map { |card| card[:title] }).to all(start_with("Opção da rua"))
      expect(result.body).not_to include("Outra rua", "Dois quartos")
    end

    it "pergunta se a pessoa aceita opções próximas quando não há correspondência" do
      apartment("Rua 3700", "Outra rua")

      result = described_class.new(lead, {}).call(messages, first_turn: true)

      expect(result).to eq("Não encontrei imóveis na rua 3600 com esses critérios. Você aceita opções próximas?")
    end
  end

end

require "rails_helper"

RSpec.describe Portal::OpenNaventXmlSerializer do
  include ActiveSupport::Testing::TimeHelpers
  it "serializes Imovelweb listings using the Vista OpenNavent shape" do
    tenant = Tenant.default
    allow(tenant).to receive(:public_base_url).and_return("https://tenant.test")
    integration = PortalIntegration.new(
      tenant: tenant,
      portal: "imovelweb",
      account_id: "47540954",
      publisher_id: "publisher-ignored"
    )
    habitation = create(
      :habitation,
      codigo: "8615",
      categoria: "Apartamento",
      status: "Aluguel",
      titulo_anuncio: "Apartamento no Centro",
      descricao_web: "Descrição pública do imóvel.",
      dormitorios_qtd: 3,
      suites_qtd: 1,
      banheiros_qtd: 2,
      vagas_qtd: 1,
      elevadores_qtd: 1,
      area_total_m2: 130,
      valor_locacao_cents: 650_000,
      valor_iptu_cents: 10_000,
      tipo_publicacao_imovelweb: "destaque",
      mostrar_mapa_imovelweb: "aproximado",
      caracteristicas: ["Ar-condicionado", "Mobiliado"],
      infra_estrutura: ["Piscina"],
      pictures: [{ "url" => "/rails/active_storage/blobs/proxy/foto.jpg" }]
    )
    habitation.create_address!(
      logradouro: "Avenida Brasil",
      numero: "3618",
      bairro: "Centro",
      cidade: "Balneário Camboriú",
      uf: "SC",
      cep: "88330-239",
      latitude: -27.0046696,
      longitude: -48.6229735
    )

    xml = described_class.new(habitations: [habitation], integration: integration).to_xml
    doc = Nokogiri::XML(xml)
    node_text = ->(path) { doc.at_xpath(path).text.strip }

    expect(doc.root.name).to eq("OpenNavent")
    expect(node_text.call("//publicador/codigoImobiliaria")).to eq("47540954")
    expect(node_text.call("//codigoAnuncio")).to eq("8615")
    expect(node_text.call("//tipoPropriedade/idTipo")).to eq("2")
    expect(node_text.call("//tipoPropriedade/idSubTipo")).to eq("1")
    expect(node_text.call("//tipoPropriedade/tipo")).to eq("Apartamento")
    expect(node_text.call("//localizacao/localidade")).to eq("Centro, Balneário Camboriú, Santa Catarina, Brasil")
    expect(node_text.call("//localizacao/mostrarMapa")).to eq("APROXIMADO")
    expect(node_text.call("//precos/preco/operacao")).to eq("ALQUILER")
    expect(node_text.call("//precos/preco/quantidade")).to eq("6500")
    expect(node_text.call("//publicacao/tipoPublicacao")).to eq("DESTACADO")
    expect(node_text.call("//caracteristica[normalize-space(nome)='AR_CONDICIONADO']/valor")).to eq("1")
    expect(node_text.call("//caracteristica[normalize-space(nome)='QUARTO']/valor")).to eq("3")
    expect(node_text.call("//multimidia/imagens/imagem/urlImagem")).to eq("https://tenant.test/rails/active_storage/blobs/proxy/foto.jpg")
  end
  def serialize(habitation, integration: nil)
    integration ||= PortalIntegration.new(tenant: Tenant.default, portal: "imovelweb", account_id: "REFERENCE-ACCOUNT")
    described_class.new(habitations: [habitation], integration: integration).to_xml
  end

  it "preserves the recovered Salute generator's Vista structure and field values" do
    habitation = build(:habitation, codigo: "VISTA-REFERENCE", categoria: "Apartamento", status: "Aluguel",
      valor_venda_cents: 0, valor_locacao_cents: 650_000, tipo_publicacao_imovelweb: "destaque",
      mostrar_mapa_imovelweb: "aproximado", dormitorios_qtd: 3, suites_qtd: 1, vagas_qtd: 1)
    reference = Nokogiri::XML(File.read(Rails.root.join("spec/fixtures/portal/salute_legacy_vista_shape.xml"))) { |c| c.strict }
    current = Nokogiri::XML(serialize(habitation)) { |c| c.strict }
    %w[//publicador/codigoImobiliaria //codigoAnuncio //codigoReferencia
       //tipoPropriedade/idTipo //tipoPropriedade/idSubTipo //tipoPropriedade/tipo
       //precos/preco/operacao //precos/preco/quantidade //precos/preco/moeda
       //publicacao/tipoPublicacao //localizacao/mostrarMapa].each do |path|
      expect(current.at_xpath(path).text.strip).to eq(reference.at_xpath(path).text.strip), path
    end
    expect(current.root.name).to eq(reference.root.name)
    expect(current.xpath("//caracteristica/id").map(&:text)).to eq(reference.xpath("//caracteristica/id").map(&:text))
  end

  it "prefers rental status over a leftover sale price" do
    habitation = build(:habitation, status: "Aluguel", valor_venda_cents: 90_000_000, valor_locacao_cents: 500_000)
    doc = Nokogiri::XML(serialize(habitation))
    expect(doc.at_xpath("//preco/operacao").text).to eq("ALQUILER")
    expect(doc.at_xpath("//preco/quantidade").text).to eq("5000")
  end

  it "keeps publication and map options in the Vista vocabulary" do
    habitation = build(:habitation, tipo_publicacao_imovelweb: "super_destaque", mostrar_mapa_imovelweb: "nao_mostrar")
    doc = Nokogiri::XML(serialize(habitation))
    expect(doc.at_xpath("//tipoPublicacao").text).to eq("SUPERDESTACADO")
    expect(doc.at_xpath("//mostrarMapa").text).to eq("NO")
  end

  it "uses the integration tenant for publisher identity and relative media URLs" do
    tenant = Tenant.create!(name: "Outro anunciante", slug: "navent-other")
    allow(tenant).to receive(:public_base_url).and_return("https://other.test")
    identity = instance_double(Tenants::PublicIdentity, email: "contato@other.test")
    expect(Tenants::PublicIdentity).to receive(:new).with(tenant).and_return(identity)
    integration = PortalIntegration.new(tenant: tenant, portal: "imovelweb", account_id: "OTHER-ACCOUNT")
    habitation = build(:habitation, tenant: tenant)
    allow(habitation).to receive(:image_urls).and_return(["/foto.jpg"])
    doc = Nokogiri::XML(serialize(habitation, integration: integration))
    expect(doc.at_xpath("//codigoImobiliaria").text).to eq("OTHER-ACCOUNT")
    expect(doc.at_xpath("//emailUsuario").text).to eq("contato@other.test")
    expect(doc.at_xpath("//urlImagem").text).to eq("https://other.test/foto.jpg")
  end

  it "streams the same valid XML with escaped titles and CDATA terminators" do
    habitation = build(:habitation, titulo_anuncio: "Apartamento & casa ]]> Centro")
    serializer = described_class.new(habitations: [habitation], integration: PortalIntegration.new(tenant: Tenant.default, portal: "imovelweb", account_id: "REF"))
    travel_to Time.zone.local(2026, 10, 21, 12, 0, 0) do
      chunks = []
      serializer.to_xml(target: chunks)
      expect(chunks.join).to eq(serializer.to_xml)
      doc = Nokogiri::XML(chunks.join) { |c| c.strict }
      expect(doc.at_xpath("//titulo").text).to eq("Apartamento & casa ]]> Centro")
      expect(doc.at_xpath("//dataModificacao").text).to eq("20261021120000")
    end
  end

  it "respects a sale-only integration even if a rental price remains on the property" do
    integration = PortalIntegration.new(tenant: Tenant.default, portal: "imovelweb", account_id: "REF", allowed_business_types: ["venda"])
    habitation = build(:habitation, status: "Aluguel", valor_venda_cents: 90_000_000, valor_locacao_cents: 500_000)
    doc = Nokogiri::XML(serialize(habitation, integration: integration))
    expect(doc.at_xpath("//preco/operacao").text).to eq("VENTA")
    expect(doc.at_xpath("//preco/quantidade").text).to eq("900000")
  end

  { "Terreno" => %w[1003 8], "Chácara" => %w[1004 10], "Sítio" => %w[1004 11],
    "Sala Comercial" => %w[1005 16], "Casa Comercial" => %w[1005 17],
    "Galpão" => %w[1005 20], "Loja" => %w[1005 19] }.each do |category, ids|
    it "keeps #{category} in its own property category" do
      doc = Nokogiri::XML(serialize(build(:habitation, categoria: category)))
      expect(doc.at_xpath("//idTipo").text).to eq(ids.first)
      expect(doc.at_xpath("//idSubTipo").text).to eq(ids.last)
    end
  end

end

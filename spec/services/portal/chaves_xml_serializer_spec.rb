require "rails_helper"

RSpec.describe Portal::ChavesXmlSerializer do
  def integration
    PortalIntegration.new(
      tenant: Tenant.default,
      portal: "chavesnamao",
      enabled: true,
      allowed_statuses: Habitation::STATUS_OPTIONS,
      allowed_business_types: %w[venda aluguel]
    )
  end

  def parse(xml)
    Nokogiri::XML(xml) { |config| config.strict }
  end

  it "emits the Chaves na Mão document structure with official property tags" do
    habitation = build(
      :habitation,
      codigo: "CNM-1",
      slug: "sala-comercial-cnm-1",
      categoria: "Sala Comercial",
      titulo_anuncio: "Sala comercial no Centro",
      descricao_web: "Descrição preparada para o portal.",
      valor_venda_cents: 900_000_00,
      valor_locacao_cents: 3_500_00,
      valor_condominio_cents: 420_00,
      valor_iptu_cents: 95_00,
      area_total_m2: 120.5,
      area_privativa_m2: 98.75,
      dormitorios_qtd: 2,
      suites_qtd: 1,
      banheiros_qtd: 2,
      vagas_qtd: 1,
      cep: "88330-000",
      numero: "270",
      complemento: "Sala 602",
      destaque_chaves_na_mao: "sim",
      periodo_locacao_chaves_na_mao: "por_mes",
      updated_at: Time.zone.parse("2026-08-06 08:37:45")
    )
    allow(habitation).to receive(:image_urls).and_return(["https://cdn.saluteimoveis.com.br/foto.jpg"])

    doc = parse(described_class.new(habitations: [habitation], integration: integration).to_xml)
    imovel = doc.at_xpath("/Document/imoveis/imovel")

    expect(doc.root.name).to eq("Document")
    expect(imovel.element_children.map(&:name)).to eq(%w[
      referencia codigo_cliente link_cliente titulo transacao transacao2 finalidade finalidade2 destaque
      tipo tipo2 valor valor_locacao valor_iptu valor_condominio area_total area_util quartos suites
      garagem banheiro closet salas despensa bar cozinha quarto_empregada escritorio area_servico
      lareira varanda lavanderia estado cidade bairro cep endereco numero complemento descritivo
      fotos_imovel data_atualizacao latitude longitude video area_comum area_privativa aceita_troca
      periodo_locacao esconder_endereco_imovel tour_360 aceita_pet
    ])
    expect(imovel.at_xpath("finalidade").text).to eq("CO")
    expect(imovel.at_xpath("tipo").text).to eq("Conj. Comercial / Sala")
    expect(imovel.at_xpath("transacao").text).to eq("V")
    expect(imovel.at_xpath("transacao2").text).to eq("L")
    expect(imovel.at_xpath("valor").text).to eq("900000.00")
    expect(imovel.at_xpath("valor_locacao").text).to eq("3500.00")
    expect(imovel.at_xpath("valor_iptu").text).to eq("95.00")
    expect(imovel.at_xpath("valor_condominio").text).to eq("420.00")
    expect(imovel.at_xpath("periodo_locacao").text).to eq("1")
    expect(imovel.at_xpath("fotos_imovel/foto/url").text).to eq("https://cdn.saluteimoveis.com.br/foto.jpg")
    expect(imovel.at_xpath("fotos_imovel/foto/data_atualizacao").text).to eq("2026-08-06 08:37:45")
    expect(doc.xpath("//contato | //caracteristicas | //principal | //ordem")).to be_empty
  end

  it "maps internal sale-only values to accepted Chaves na Mão values" do
    habitation = build(
      :habitation,
      codigo: "CNM-2",
      categoria: "Casa em Condomínio",
      valor_venda_cents: 1_250_000_00,
      valor_locacao_cents: 0,
      periodo_locacao_chaves_na_mao: "imovel_de_venda"
    )
    allow(habitation).to receive(:image_urls).and_return(["https://cdn.saluteimoveis.com.br/casa.jpg"])

    imovel = parse(described_class.new(habitations: [habitation], integration: integration).to_xml).at_xpath("/Document/imoveis/imovel")

    expect(imovel.at_xpath("finalidade").text).to eq("RE")
    expect(imovel.at_xpath("tipo").text).to eq("Casa / Sobrado em Condomínio")
    expect(imovel.at_xpath("transacao").text).to eq("V")
    expect(imovel.at_xpath("transacao2").text).to be_empty
    expect(imovel.at_xpath("valor_locacao").text).to be_empty
    expect(imovel.at_xpath("periodo_locacao").text).to be_empty
  end
end

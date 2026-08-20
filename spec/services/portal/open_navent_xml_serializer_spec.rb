require "rails_helper"

RSpec.describe Portal::OpenNaventXmlSerializer do
  def integration_for
    PortalIntegration.new(
      tenant: Tenant.default,
      portal: "casamineira",
      enabled: true,
      allowed_statuses: Habitation::STATUS_OPTIONS,
      allowed_business_types: %w[venda aluguel]
    )
  end

  it "serializes Casa Mineira in the OpenNavent structure" do
    habitation = build(
      :habitation,
      codigo: "CM-XML",
      categoria: "Apartamento",
      titulo_anuncio: "Apartamento no Centro",
      descricao_web: "Descricao comercial do imovel.",
      valor_venda_cents: 500_000_00,
      dormitorios_qtd: 2,
      banheiros_qtd: 1,
      vagas_qtd: 1
    )

    xml = described_class.new(habitations: [habitation], integration: integration_for).to_xml

    expect(xml).to include("<OpenNavent>")
    expect(xml).to include("<dataModificacao>")
    expect(xml).to include("<codigoAnuncio>", "<![CDATA[CM-XML]]>")
    expect(xml).to include("<tipoPropriedade>")
    expect(xml).to include("<tipo>", "<![CDATA[Residencial]]>")
    expect(xml).to include("<subTipo>", "<![CDATA[Apartamento]]>")
    expect(xml).to include("<operacao>Venda</operacao>")
    expect(xml).to include("<preco>500000</preco>")
    expect(xml).to include("<moeda>BRL</moeda>")
    expect(xml).to include("<imagens>")
  end

  it "marks condominium as absent when the fee is blank or zero" do
    habitation = build(
      :habitation,
      codigo: "CM-SEM-CONDOMINIO",
      valor_condominio_cents: 0
    )

    xml = described_class.new(habitations: [habitation], integration: integration_for).to_xml

    expect(xml).to include("<valorCondominio>")
    expect(xml).to include("<![CDATA[Sem Condominio]]>")
  end

  it "marks condominium as absent when cents would serialize as zero reais" do
    habitation = build(
      :habitation,
      codigo: "CM-CONDOMINIO-ZERADO",
      valor_condominio_cents: 1
    )

    xml = described_class.new(habitations: [habitation], integration: integration_for).to_xml

    expect(xml).to include("<valorCondominio>")
    expect(xml).to include("<![CDATA[Sem Condominio]]>")
    expect(xml).not_to include("<valorCondominio>0</valorCondominio>")
  end

  it "keeps the condominium fee numeric when present" do
    habitation = build(
      :habitation,
      codigo: "CM-CONDOMINIO",
      valor_condominio_cents: 430_00
    )

    xml = described_class.new(habitations: [habitation], integration: integration_for).to_xml

    expect(xml).to include("<valorCondominio>430</valorCondominio>")
    expect(xml).not_to include("Sem Condominio")
  end
end

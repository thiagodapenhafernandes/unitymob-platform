require "rails_helper"

RSpec.describe Seo::PropertyMetadataBuilder do
  let(:tenant) { Tenant.default }
  let(:development) do
    create(:habitation, tenant: tenant, tipo: "Empreendimento", nome_empreendimento: "Residencial de Nome Longo", slug: "slug-legado-preservado")
  end

  it "keeps city and commercial intent even when the title is long, preserving the slug" do
    development.update_columns(slug: "slug-legado-preservado")
    create(:habitation, tenant: tenant, codigo_empreendimento: development.codigo, suites_qtd: 1, vagas_qtd: 1)
    metadata = described_class.new(development).attributes
    expect(metadata[:meta_title]).to include("Residencial de Nome Longo em Centro, Balneário Camboriú", "imóveis à venda")
    expect(metadata[:meta_description]).to include("Confira imóveis à venda", "1 suíte", "1 vaga")
    expect(metadata[:canonical_path]).to eq("/empreendimento/slug-legado-preservado")
    expect(metadata[:og_title]).to eq(metadata[:meta_title])
  end

  it "uses only published units of the same tenant to describe the offer" do
    create(:habitation, tenant: tenant, codigo_empreendimento: development.codigo, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 300_000)
    create(:habitation, tenant: tenant, codigo_empreendimento: development.codigo, exibir_no_site_flag: false)
    other = Tenant.create!(name: "Outro estoque", slug: "other-development-metadata")
    create(:habitation, tenant: other, tipo: "Empreendimento", codigo: development.codigo, nome_empreendimento: "Empreendimento da outra conta")
    create(:habitation, tenant: other, codigo_empreendimento: development.codigo)

    metadata = described_class.new(development).attributes
    expect(metadata[:meta_title]).to include("imóveis para alugar")
    expect(metadata[:meta_title]).not_to include("à venda")
  end

  it "describes both transactions only when both are publicly available" do
    create(:habitation, tenant: tenant, codigo_empreendimento: development.codigo)
    create(:habitation, tenant: tenant, codigo_empreendimento: development.codigo, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 300_000)
    expect(described_class.new(development).attributes[:meta_title]).to include("imóveis à venda e para alugar")
  end

  it "does not promise available stock when there are no published units" do
    metadata = described_class.new(development).attributes
    expect(metadata[:meta_title]).not_to include("à venda", "para alugar")
    expect(metadata[:meta_description]).not_to include("à venda", "para alugar", "disponíveis")
  end

  it "preserves editorial metadata" do
    development.update!(meta_title: "Título aprovado", meta_description: "Descrição aprovada")
    metadata = described_class.new(development).attributes
    expect(metadata[:meta_title]).to start_with("Título aprovado | ")
    expect(metadata[:meta_description]).to eq("Descrição aprovada")
  end
end

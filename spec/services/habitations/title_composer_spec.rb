# frozen_string_literal: true

require "rails_helper"

RSpec.describe Habitations::TitleComposer do
  def compose(bairro: "Barra Sul", **attrs)
    habitation = build(:habitation, **attrs)
    habitation.address ||= habitation.build_address
    habitation.address.bairro = bairro
    described_class.compose(habitation)
  end

  it "composes sale title with contraction and suítes rule" do
    result = compose(categoria: "Apartamento", status: "Venda", valor_venda_cents: 500_000_00,
                     dormitorios_qtd: 3, suites_qtd: 3, bairro: "Barra Sul",
                     nome_empreendimento: "Copenhagen")

    expect(result.title).to eq("Apartamento à venda 3 suítes na Barra Sul | Copenhagen")
    expect(result.tier).to eq(:full)
    expect(result.skip_reason).to be_nil
  end

  it "composes rental title" do
    result = compose(categoria: "Apartamento", status: "Aluguel", valor_venda_cents: 0,
                     valor_locacao_cents: 5_000_00, dormitorios_qtd: 2, suites_qtd: 1,
                     bairro: "Centro", nome_empreendimento: "Dona Matilde")

    expect(result.title).to eq("Apartamento Aluguel Anual 2 dormitórios, 1 suíte no Centro | Dona Matilde")
  end

  it "falls back to 'em' for unmapped neighborhoods" do
    result = compose(bairro: "Ariribá", nome_empreendimento: "Residencial Maré")

    expect(result.title).to include("em Ariribá | Residencial Maré")
  end

  it "omits location when bairro is blank" do
    result = compose(bairro: "", nome_empreendimento: "Copenhagen")

    expect(result.title).to match(/\| Copenhagen$/)
    expect(result.title).not_to include("em  |")
  end

  it "omits bedrooms when both counts are zero" do
    result = compose(categoria: "Terreno", dormitorios_qtd: 0, suites_qtd: 0,
                     bairro: "Centro", nome_empreendimento: "Loteamento X")

    expect(result.title).to eq("Terreno à venda no Centro | Loteamento X")
  end

  it "skips generic empreendimento names" do
    expect(compose(categoria: "Terreno", nome_empreendimento: "Terreno").skip_reason)
      .to eq(:invalid_empreendimento)
    expect(compose(nome_empreendimento: "AB").skip_reason).to eq(:invalid_empreendimento)
    expect(compose(nome_empreendimento: "  ").skip_reason).to eq(:invalid_empreendimento)
  end

  it "skips records without categoria or determinable transaction" do
    expect(compose(categoria: "").skip_reason).to eq(:blank_categoria)
    expect(compose(status: "Suspenso", valor_venda_cents: 0, valor_locacao_cents: 0,
                   nome_empreendimento: "Copenhagen").skip_reason).to eq(:unknown_transaction)
  end

  it "drops clauses to respect the 80-char limit" do
    long_emp = "Residencial Parque das Flores"
    result = compose(categoria: "Apartamento", dormitorios_qtd: 4, suites_qtd: 2,
                     bairro: "São Francisco de Assis", nome_empreendimento: long_emp)

    expect(result.title.length).to be <= 80
    expect(result.tier).to eq(:no_bedrooms)
    expect(result.title).to end_with("| #{long_emp}")
  end
end

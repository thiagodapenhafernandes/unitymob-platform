require "rails_helper"

RSpec.describe PublicSite::PriceRanges do
  let(:tenant) { Tenant.create!(name: "Faixas", slug: "faixas-auto") }

  it "calcula limites e faixas redondas pelo estoque de venda da conta" do
    [800_000, 1_200_000, 1_500_000, 2_000_000, 2_400_000, 3_100_000, 4_000_000, 5_500_000, 9_000_000, 12_000_000].each do |reais|
      create(:habitation, tenant: tenant, valor_venda_cents: reais * 100, valor_locacao_cents: 0)
    end

    sale = described_class.new(tenant).call.fetch("venda")

    expect(sale[:count]).to eq(10)
    expect(sale[:min]).to be <= 800_000
    expect(sale[:max]).to be >= 11_000_000
    expect(sale[:ranges].first.first).to start_with("Até R$")
    expect(sale[:ranges].last.first).to start_with("Acima de R$")
    expect(sale[:ranges].last.last).to end_with("-")
    expect(described_class.new(tenant).call).not_to have_key("aluguel")
  end

  it "não sugere nada com poucos imóveis" do
    3.times { create(:habitation, tenant: tenant, valor_venda_cents: 1_000_000_00) }

    expect(described_class.new(tenant).call).to eq({})
  end

  it "gera rótulos curtos em reais" do
    expect(described_class.label_for(0, 1_500_000)).to eq("Até R$ 1,5 mi")
    expect(described_class.label_for(1_500_000, 3_000_000)).to eq("R$ 1,5 mi a R$ 3 mi")
    expect(described_class.label_for(18_000, 0)).to eq("Acima de R$ 18 mil")
  end
end

require "rails_helper"

RSpec.describe Habitation, "promoção de preço (venda/locação)", type: :model do
  it "marca promoção na queda e a remove no aumento (venda)" do
    h = create(:habitation, valor_venda_cents: 1_000_00)

    h.update!(valor_venda_cents: 900_00)
    h.reload
    expect(h.sale_discount?).to be(true)
    expect(h.valor_venda_anterior_cents).to eq(1_000_00)
    expect(h.valor_promocional_cents).to eq(900_00)

    h.update!(valor_venda_cents: 1_200_00)
    h.reload
    expect(h.sale_discount?).to be(false)
    expect(h.valor_venda_anterior_cents).to be_blank
    expect(h.valor_promocional_cents).to be_blank
  end

  it "marca promoção na queda e a remove no aumento (locação)" do
    h = create(:habitation, valor_locacao_cents: 5_000_00)

    h.update!(valor_locacao_cents: 4_000_00)
    h.reload
    expect(h.rent_discount?).to be(true)
    expect(h.valor_locacao_anterior_cents).to eq(5_000_00)
    expect(h.valor_promocional_cents).to eq(4_000_00)

    h.update!(valor_locacao_cents: 6_000_00)
    h.reload
    expect(h.rent_discount?).to be(false)
    expect(h.valor_locacao_anterior_cents).to be_blank
    expect(h.valor_promocional_cents).to be_blank
  end

  it "respeita valor_venda_anterior_cents atribuído explicitamente (ex.: Vista)" do
    h = create(:habitation, valor_venda_cents: 800_00)
    # simula import que sobe o preço mas envia o anterior explicitamente
    h.update!(valor_venda_cents: 1_000_00, valor_venda_anterior_cents: 1_200_00)
    h.reload
    expect(h.valor_venda_anterior_cents).to eq(1_200_00)
  end
end

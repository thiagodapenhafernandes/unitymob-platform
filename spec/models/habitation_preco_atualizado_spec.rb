require "rails_helper"

RSpec.describe Habitation, "preco_atualizado_em", type: :model do
  it "não marca no cadastro inicial" do
    h = create(:habitation, valor_venda_cents: 1_000_00)
    expect(h.preco_atualizado_em).to be_nil
  end

  it "marca quando o valor de venda muda" do
    h = create(:habitation, valor_venda_cents: 1_000_00)
    expect { h.update!(valor_venda_cents: 1_100_00) }
      .to change { h.reload.preco_atualizado_em }.from(nil).to(be_present)
  end

  it "marca quando o valor de locação muda" do
    h = create(:habitation, valor_venda_cents: 0, valor_locacao_cents: 5_000_00)
    expect { h.update!(valor_locacao_cents: 4_500_00) }
      .to change { h.reload.preco_atualizado_em }.from(nil).to(be_present)
  end

  it "não marca quando outro campo (não-preço) muda" do
    h = create(:habitation, valor_venda_cents: 1_000_00)
    expect { h.update!(bairro: "Novo Bairro #{SecureRandom.hex(2)}") }
      .not_to change { h.reload.preco_atualizado_em }
  end
end

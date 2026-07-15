require "rails_helper"

RSpec.describe Habitation, "rótulo do valor comercializado no histórico", type: :model do
  it "não rotula 'por terceiros' ao mudar para 'Alugado imobiliária'" do
    h = create(:habitation, status: "Venda", valor_venda_cents: 500_000_00, exibir_no_site_flag: true)

    h.update!(status: "Alugado imobiliária", valor_alugado_terceiros_cents: 3_000_00)

    labels = h.habitation_audit_logs.order(:created_at).last.change_summaries.map { |s| s[:label] }
    expect(labels).to include("Valor comercializado (locação)")
    expect(labels).not_to include(a_string_matching(/por terceiros/i))
  end

  it "usa rótulo neutro de venda para 'Vendido imobiliária'" do
    h = create(:habitation, status: "Venda", valor_venda_cents: 500_000_00)

    h.update!(status: "Vendido imobiliária", valor_vendido_terceiros_cents: 480_000_00)

    labels = h.habitation_audit_logs.order(:created_at).last.change_summaries.map { |s| s[:label] }
    expect(labels).to include("Valor comercializado (venda)")
    expect(labels).not_to include(a_string_matching(/por terceiros/i))
  end
end

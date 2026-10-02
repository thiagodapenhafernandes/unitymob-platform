require "rails_helper"

RSpec.describe PublicSite::DevelopmentUnitMetrics do
  let(:tenant) { Tenant.default }

  def build_unit(dev_codigo, **overrides)
    create(:habitation, tenant: tenant, codigo: dev_codigo, tipo: "Empreendimento") unless tenant.habitations.exists?(codigo: dev_codigo)
    create(:habitation, tenant: tenant, codigo_empreendimento: dev_codigo, **overrides)
  end

  it "conta só unidades visíveis no site e com preço" do
    build_unit("DEV-1")
    build_unit("DEV-1", valor_locacao_cents: 300_000, valor_venda_cents: 0, status: "Aluguel")
    build_unit("DEV-1", exibir_no_site_flag: false)
    build_unit("DEV-1", status: "Diária")
    build_unit("DEV-1", valor_venda_cents: 0, valor_locacao_cents: 0)
    build_unit("DEV-2")

    counts = described_class.new(tenant.habitations, ["DEV-1", "DEV-2"]).unit_counts

    expect(counts).to eq({ "DEV-1" => 2, "DEV-2" => 1 })
  end

  it "devolve vazio sem códigos" do
    build_unit("DEV-1")

    expect(described_class.new(tenant.habitations, []).unit_counts).to eq({})
  end
end

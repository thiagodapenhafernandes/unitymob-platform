require "rails_helper"

RSpec.describe Dashboard::CaptacaoScope do
  let(:tenant) { Tenant.default }
  let(:starts_at) { Date.new(2026, 9, 1) }
  let(:ends_at) { Date.new(2026, 9, 30) }

  def captacao(codigo, **overrides)
    defaults = {
      tenant: tenant, codigo: codigo,
      intake_origin: Habitation::INTAKE_ORIGIN_BROKER,
      intake_status: "published",
      admin_reviewed_at: Time.zone.local(2026, 9, 10, 12),
      valor_locacao_cents: 200_000, valor_venda_cents: 0
    }
    create(:habitation, **defaults.merge(overrides))
  end

  it "conta pela aprovação no período, incluindo admin_approved e cadastro anterior" do
    captacao("CAP-1")
    captacao("CAP-2", intake_status: "admin_approved")
    captacao("CAP-3", data_cadastro_crm: Time.zone.local(2026, 8, 20), created_at: Time.zone.local(2026, 8, 20))
    captacao("OUT-1", admin_reviewed_at: Time.zone.local(2026, 8, 15, 12))
    captacao("OUT-2", intake_origin: nil, intake_status: nil, admin_reviewed_at: nil)
    captacao("OUT-3", valor_locacao_cents: 0, valor_venda_cents: 50_000_000)

    scope = described_class.call(tenant: tenant, starts_at: starts_at, ends_at: ends_at, kind: "locacao")

    expect(scope.order(:codigo).pluck(:codigo)).to eq(%w[CAP-1 CAP-2 CAP-3])
  end

  it "separa venda de locação" do
    captacao("VENDA-1", valor_locacao_cents: 0, valor_venda_cents: 50_000_000)

    venda = described_class.call(tenant: tenant, starts_at: starts_at, ends_at: ends_at, kind: "venda")
    locacao = described_class.call(tenant: tenant, starts_at: starts_at, ends_at: ends_at, kind: "locacao")

    expect(venda.pluck(:codigo)).to eq(["VENDA-1"])
    expect(locacao.pluck(:codigo)).to be_empty
  end

  it "restringe por donos quando informado" do
    owner = create(:admin_user, tenant: tenant)
    captacao("MINE-1", admin_user: owner)
    captacao("OTHER-1")

    scope = described_class.call(tenant: tenant, starts_at: starts_at, ends_at: ends_at,
                                 kind: "locacao", owner_ids: [owner.id])

    expect(scope.pluck(:codigo)).to eq(["MINE-1"])
  end

  it "rejeita kind inválido" do
    expect {
      described_class.call(tenant: tenant, starts_at: starts_at, ends_at: ends_at, kind: "x")
    }.to raise_error(ArgumentError)
  end
end

require "rails_helper"

RSpec.describe HabitationIntakeSplitter do
  let(:tenant) { Tenant.default }
  let(:admin) { create(:admin_user, tenant: tenant) }
  let(:submitted_at) { Time.zone.local(2026, 7, 16, 10, 30, 0) }

  before do
    Current.tenant = tenant
    @baseline_codigo = (Habitation.highest_numeric_codigo + 100).to_s
    create(:habitation, tenant: tenant, codigo: @baseline_codigo)
  end

  it "troca o codigo de rascunho por codigo definitivo e carimba a data de cadastro no envio" do
    intake = create(:habitation, :broker_intake, tenant: tenant, admin_user: admin, codigo: nil)
    expected_codigo = Habitation.next_automatic_codigo

    expect(intake.codigo).to start_with(Habitation::TEMPORARY_CODIGO_PREFIX)
    expect(intake.data_cadastro_crm).to be_nil

    result = described_class.new(intake, submitted_at: submitted_at).call!

    expect(result).to eq([intake])
    expect(intake.reload).to have_attributes(
      codigo: expected_codigo,
      data_cadastro_crm: submitted_at,
      submitted_for_review_at: submitted_at,
      intake_status: "submitted_for_admin_review"
    )
    expect(intake.codigo).not_to start_with(Habitation::TEMPORARY_CODIGO_PREFIX)
  end

  it "mantem codigo definitivo existente ao reenviar para revisao" do
    intake = create(
      :habitation,
      :broker_intake,
      tenant: tenant,
      admin_user: admin,
      codigo: (Habitation.highest_numeric_codigo + 100).to_s,
      data_cadastro_crm: submitted_at - 1.day,
      intake_status: "returned_to_broker"
    )
    original_codigo = intake.codigo

    described_class.new(intake, submitted_at: submitted_at).call!

    expect(intake.reload).to have_attributes(
      codigo: original_codigo,
      data_cadastro_crm: submitted_at - 1.day,
      submitted_for_review_at: submitted_at,
      intake_status: "submitted_for_admin_review"
    )
  end

  it "gera codigos definitivos distintos para venda e locacao quando a captacao e ambos" do
    intake = create(
      :habitation,
      :broker_intake,
      tenant: tenant,
      admin_user: admin,
      codigo: nil,
      intake_modalidade: "ambos",
      valor_venda_cents: 1_200_000_00,
      valor_locacao_cents: 8_000_00
    )
    expected_first_codigo = Habitation.next_automatic_codigo
    expected_second_codigo = (expected_first_codigo.to_i + 1).to_s

    result = described_class.new(intake, submitted_at: submitted_at).call!
    records = result.map(&:reload)

    expect(records.size).to eq(2)
    expect(records.map(&:codigo)).to all(match(/\A\d+\z/))
    expect(records.map(&:codigo)).to contain_exactly(expected_first_codigo, expected_second_codigo)
    expect(records.map(&:data_cadastro_crm)).to all(eq(submitted_at))
    expect(records.map(&:submitted_for_review_at)).to all(eq(submitted_at))
    expect(records.map(&:intake_status)).to all(eq("submitted_for_admin_review"))
  end
end

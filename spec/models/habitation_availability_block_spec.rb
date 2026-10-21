require "rails_helper"

RSpec.describe HabitationAvailabilityBlock do
  let(:habitation) { create(:habitation, status: "Diária") }
  let(:attributes) { { habitation: habitation, tenant: habitation.tenant, starts_on: "2026-12-20", ends_on: "2026-12-25" } }

  it "aceita um dia, rejeita intervalo invertido e exige datas" do
    expect(described_class.new(attributes.merge(ends_on: "2026-12-20"))).to be_valid
    expect(described_class.new(attributes.merge(ends_on: "2026-12-19"))).not_to be_valid
    expect(described_class.new(attributes.merge(starts_on: "inválida"))).not_to be_valid
  end

  it "rejeita sobreposição inclusiva e permite o dia seguinte" do
    described_class.create!(attributes)
    expect(described_class.new(attributes.merge(starts_on: "2026-12-25", ends_on: "2026-12-28"))).not_to be_valid
    expect(described_class.new(attributes.merge(starts_on: "2026-12-26", ends_on: "2026-12-28"))).to be_valid
  end

  it "reconfere sobreposição sob lock quando outro bloqueio surgiu após a validação" do
    candidate = described_class.new(attributes)
    expect(candidate).to be_valid
    described_class.create!(attributes)
    expect { candidate.save!(validate: false) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(habitation.availability_blocks.count).to eq(1)
  end

  it "não permite vincular bloqueio de outra conta nem imóvel anual" do
    other = Tenant.create!(name: "Outra calendário", slug: "outra-calendario-#{SecureRandom.hex(3)}")
    expect(described_class.new(attributes.merge(tenant: other))).not_to be_valid
    habitation.update!(status: "Aluguel")
    expect(described_class.new(attributes)).not_to be_valid
  end

  it "isola os períodos de imóveis diferentes e remove blocos ao excluir o imóvel" do
    described_class.create!(attributes)
    other_property = create(:habitation, status: "Diária")
    expect(described_class.new(attributes.merge(habitation: other_property))).to be_valid
    expect { habitation.destroy! }.to change(described_class, :count).by(-1)
  end
end

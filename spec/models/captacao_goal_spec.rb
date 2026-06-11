require "rails_helper"

RSpec.describe CaptacaoGoal, type: :model do
  it "sincroniza o ano pela data inicial" do
    goal = build(:captacao_goal, start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 30))

    goal.validate

    expect(goal.year).to eq(2026)
  end

  it "bloqueia metas sobrepostas para o mesmo tipo" do
    create(:captacao_goal, kind: :venda, start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 30))

    goal = build(:captacao_goal, kind: :venda, start_date: Date.new(2026, 6, 15), end_date: Date.new(2026, 7, 15))

    expect(goal).not_to be_valid
    expect(goal.errors[:base]).to include("Já existe uma meta de venda com período sobreposto")
  end

  it "permite períodos iguais para tipos diferentes" do
    create(:captacao_goal, kind: :venda, start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 30))

    goal = build(:captacao_goal, kind: :locacao, start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 30))

    expect(goal).to be_valid
  end

  it "soma metas que cruzam o período informado" do
    create(:captacao_goal, kind: :venda, target: 10, start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 30))
    create(:captacao_goal, kind: :venda, target: 20, start_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 7, 31))
    create(:captacao_goal, kind: :locacao, target: 99, start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 30))

    target = CaptacaoGoal.current_target(
      kind: :venda,
      start_date: Date.new(2026, 6, 15),
      end_date: Date.new(2026, 7, 15)
    )

    expect(target).to eq(30)
  end
end

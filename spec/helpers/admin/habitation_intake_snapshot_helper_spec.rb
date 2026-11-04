require "rails_helper"

RSpec.describe Admin::HabitationsHelper, type: :helper do
  it "oculta campos vazios e seções vazias sem apagar fotografia ou dados preenchidos" do
    snapshot = { "sections" => [
      { "key" => "identificacao", "rows" => [{ "label" => "Modalidade", "value" => "Diária" }, { "value" => "-" }, { "value" => " " }] },
      { "key" => "proprietario", "rows" => [{ "value" => "Contato restrito" }] },
      { "key" => "vazio", "rows" => [{ "value" => nil }] }
    ] }
    original = snapshot.deep_dup
    sections = helper.habitation_intake_snapshot_sections(snapshot, include_owner: false)
    expect(sections.size).to eq(1)
    expect(sections.first["rows"]).to eq([{ "label" => "Modalidade", "value" => "Diária" }])
    expect(snapshot).to eq(original)
    expect(helper.habitation_intake_snapshot_sections(snapshot, include_owner: true).size).to eq(2)
  end
end

require "rails_helper"

RSpec.describe Leads::FormResponses do
  before { allow_any_instance_of(Lead).to receive(:route_lead) }

  it "mostra todos os valores brutos da Meta, inclusive de cadastros antigos" do
    lead = create(:lead, product: "Campanha Locação", other_information: {
      "meta_leadgen_id" => "original", "field_data" => [
        { "name" => "preferências_do_imóvel", "values" => ["Sacada", "Garagem"] },
        { "name" => "autorizo_contato?", "values" => ["NÃO"] }
      ] }, custom_answers: [{ "key" => "preferências_do_imóvel", "answer" => "Sacada" }])
    groups = described_class.new(lead).groups
    expect(groups.size).to eq(1)
    expect(groups.first).to include(provider: "Meta", form_name: "Campanha Locação")
    expect(groups.first[:answers]).to include(
      { question: "Preferências do imóvel", answer: "Sacada\nGaragem" },
      { question: "Autorizo contato?", answer: "NÃO" })
  end

  it "separa campanhas agregadas ao mesmo contato sem repetir a primeira consulta" do
    lead = create(:lead, other_information: { "meta_leadgen_id" => "first",
      "field_data" => [{ "name" => "prazo", "values" => ["30 dias"] }] })
    lead.activities.create!(kind: "inquiry_complemented", metadata: {
      inquiry_information: { meta_leadgen_id: "first", meta_form_name: "Primeira campanha",
        field_data: [{ name: "prazo", values: ["30 dias"] }] } })
    lead.activities.create!(kind: "inquiry_complemented", metadata: {
      inquiry_information: { meta_leadgen_id: "second", meta_form_name: "Segunda campanha" },
      inquiry_answers: [{ key: "prazo", answer: "Imediato" }] })
    groups = described_class.new(lead).groups
    expect(groups.map { |group| group[:event_id] }).to eq(%w[second first])
    expect(groups.map { |group| group[:form_name] }).to eq(["Segunda campanha", "Primeira campanha"])
    expect(groups.first[:answers]).to eq([{ question: "prazo", answer: "Imediato" }])
  end

  it "preserva os formulários de LinkedIn e TikTok e ignora dados sem perguntas" do
    lead = create(:lead, other_information: { "linkedin_answers" => { "Área de interesse" => ["Centro", "Praia"] },
      "tiktok_answers" => { "Orçamento" => "7500" } })
    expect(described_class.new(lead).groups.map { |group| group[:provider] }).to contain_exactly("LinkedIn", "TikTok")
    expect(described_class.new(create(:lead)).groups).to eq([])
  end
end

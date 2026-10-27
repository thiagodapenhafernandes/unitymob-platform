require "rails_helper"

RSpec.describe "admin/shared/ui/_stage_conversion_fields", type: :view do
  before do
    allow(view).to receive(:stage_conversion_integration_state).and_return(:missing)
  end

  def render_fields(provider = "google", board: true)
    render partial: "admin/shared/ui/stage_conversion_fields", locals: {
      provider: provider, field_prefix: "conversion-#{provider}", selected: provider == "google" ? "visit" : "Schedule",
      selected_trigger: "visit_completed", board: board, input_prefix: "stages[0]"
    }
    Nokogiri::HTML.fragment(rendered)
  end

  it "desabilita controles sem integração e preserva os valores do formulário" do
    html = render_fields(board: false)
    expect(html.css("select[disabled]").count).to eq(2)
    expect(html.at_css('input[type="hidden"][name="stages[0][google_event]"]')["value"]).to eq("visit")
    expect(html.text).to include("Configure a integração Google", "Quando disparar")
  end

  it "permite preparar a etapa sem ativar uma integração pausada" do
    allow(view).to receive(:stage_conversion_integration_state).with("google").and_return(:paused)
    html = render_fields
    expect(html.css("select[disabled]")).to be_empty
    expect(html.text).to include("Salvar esta etapa não ativa o envio")
    expect(html.at_css('[data-lead-status-field="google_event_trigger"]')).to be_present
  end

  it "reutiliza os mesmos controles para a Meta" do
    html = render_fields("meta")
    expect(html.at_css('[data-lead-status-field="meta_conversion_event"]')).to be_present
    expect(html.at_css('[data-lead-status-field="meta_event_trigger"]')).to be_present
  end
end

require "rails_helper"

RSpec.describe "public_habitations_index_refresh.css" do
  let(:stylesheet) { Rails.root.join("app/assets/stylesheets/public_habitations_index_refresh.css").read }

  it "mantem contraste dos botoes primarios e opcoes selecionadas no site publico" do
    expect(stylesheet).to include(
      ".public-habitations-index__apply-button,",
      "color: #fff !important;",
      ".public-habitations-index__drawer .public-habitations-index__primary-button.bg-blue-three",
      ".public-habitations-index__drawer input.peer:checked + div",
      "background: var(--phi-navy) !important;"
    )
  end
end

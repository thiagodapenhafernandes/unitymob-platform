require "rails_helper"

RSpec.describe "Public global search drawer contract" do
  subject(:stylesheet) { Rails.root.join("app/assets/stylesheets/components/_public_global_search_drawer.scss").read }

  it "mantém autocomplete, radios de quantidade, destaques e características com estados selecionados" do
    expect(stylesheet).to include(".public-global-search__autocomplete")
    expect(stylesheet).to include(".public-global-search__quantity-options")
    expect(stylesheet).to include(".public-global-search__quantity-input:checked + span")
    expect(stylesheet).to include(".public-global-search__highlights")
    expect(stylesheet).to include(".public-global-search__highlight-input:checked + .public-global-search__switch")
    expect(stylesheet).to include(".public-global-search__features")
    expect(stylesheet).to include(".public-global-search__feature-input:checked + .public-global-search__switch")
  end

  it "mantém o botão flutuante em uma camada fixa e clicável" do
    expect(stylesheet).to include("position: fixed;")
    expect(stylesheet).to include("z-index: 2147481000;")
    expect(stylesheet).to include("pointer-events: none;")
    expect(stylesheet).to include("pointer-events: auto;")
  end
end

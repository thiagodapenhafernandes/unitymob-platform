require "rails_helper"

RSpec.describe "Public global search drawer contract" do
  subject(:stylesheet) { Rails.root.join("app/assets/stylesheets/components/_public_global_search_drawer.scss").read }

  it "estiliza a variante default do FAB e do drawer com a paleta da conta" do
    expect(stylesheet).to include(".public-theme-filter-fab--default")
    expect(stylesheet).to include(".public-theme-filter-drawer--default")
    expect(stylesheet).to include("var(--color-primary")
    expect(stylesheet).to include("var(--color-accent")
  end

  it "mantém estados selecionados de pills, buscas rápidas, destaques e combobox" do
    expect(stylesheet).to include('.public-theme-filter-drawer__pill[aria-pressed="true"]')
    expect(stylesheet).to include(".public-theme-filter-drawer__chip:has(.public-theme-filter-drawer__quick-input:checked)")
    expect(stylesheet).to include(".public-theme-filter-drawer__toggle:has(.public-theme-filter-drawer__toggle-input:checked)")
    expect(stylesheet).to include(".public-theme-combobox__option.selected")
  end

  it "mantém o botão flutuante em uma camada fixa e clicável" do
    expect(stylesheet).to include("position: fixed;")
    expect(stylesheet).to include("z-index: 2147481000;")
    expect(stylesheet).to include("pointer-events: none;")
    expect(stylesheet).to include("pointer-events: auto;")
  end
end

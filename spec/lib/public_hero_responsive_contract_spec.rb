require "rails_helper"

RSpec.describe "Responsividade do hero público" do
  let(:hero_partial) { Rails.root.join("app/views/home/_hero.html.erb").read }
  let(:search_partial) { Rails.root.join("app/views/shared/_search_hero_imobill.html.erb").read }
  let(:hero_styles) { Rails.root.join("app/assets/stylesheets/components/_hero.scss").read }

  it "limita a tipografia mobile e reserva espaço para o header fixo" do
    expect(hero_partial).to include("hero-title")
    expect(hero_partial).to include("hero-subtitle")
    expect(hero_styles).to include("padding-top: calc(5rem + env(safe-area-inset-top))")
    expect(hero_styles).to include("font-size: clamp(1.75rem, 7.6vw, 2.35rem)")
    expect(hero_styles).to include("overflow-wrap: anywhere")
  end

  it "mantém os atalhos da busca em uma linha nas telas estreitas" do
    expect(search_partial).to include("hero-search-shortcuts")
    expect(search_partial).to include('<span class="sm:hidden">Empreend.</span>')
    expect(search_partial).to include("whitespace-nowrap")
  end
end

RSpec.shared_examples "contrato do hero público" do
  it "expõe os ganchos canônicos na variante padrão" do
    expect(hero_standard_source).to include("public-theme-hero--default")
    expect(hero_standard_source).to include("public-theme-hero__title")
    expect(hero_standard_source).to include("public-theme-hero__lead")
    expect(hero_standard_source).to include("public-theme-hero__search")
    expect(hero_standard_source).to include("public-theme-hero__overlay")
  end

  it "expõe os mesmos ganchos na variante luxury" do
    expect(hero_luxury_source).to include("public-theme-hero--")
    expect(hero_luxury_source).to include("public-theme-hero__title")
    expect(hero_luxury_source).to include("public-theme-hero__lead")
    expect(hero_luxury_source).to include("public-theme-hero__search")
    expect(hero_luxury_source).to include("public-theme-hero__overlay")
  end
end

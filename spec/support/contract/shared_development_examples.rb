RSpec.shared_examples "contrato do empreendimento público" do
  it "expõe as regiões canônicas no empreendimento padrão" do
    expect(development_standard_source).to include("public-theme-development-about--default")
    expect(development_standard_source).to include("public-theme-development-features--default")
    expect(development_standard_source).to include("public-theme-development-location--default")
    expect(development_standard_source).to include("public-theme-development-units--default")
    expect(development_standard_source).to include("public-theme-developments--default")
    expect(development_standard_source).to include("public-theme-developments__grid")
  end

  it "expõe as mesmas regiões na variante luxury" do
    expect(development_luxury_source).to include("public-theme-development-about--")
    expect(development_luxury_source).to include("public-theme-development-features--")
    expect(development_luxury_source).to include("public-theme-development-location--")
    expect(development_luxury_source).to include("public-theme-development-units--")
  end
end

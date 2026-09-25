RSpec.shared_examples "contrato do cabeçalho e rodapé públicos" do
  it "expõe os ganchos canônicos no cabeçalho e rodapé padrão" do
    expect(header_standard_source).to include("public-theme-header--default")
    expect(header_standard_source).to include("public-theme-header__brand")
    expect(header_standard_source).to include("public-theme-header__nav")
    expect(footer_standard_source).to include("public-theme-site-footer--default")
  end

  it "expõe os mesmos ganchos na variante luxury" do
    expect(header_luxury_source).to include("public-theme-header--")
    expect(header_luxury_source).to include("public-theme-header__brand")
    expect(header_luxury_source).to include("public-theme-header__nav")
    expect(footer_luxury_source).to include("public-theme-site-footer--")
  end

  it "mantém o escopo do tema no shell (padrão) e na variante luxury" do
    expect(shell_standard_source).to include('data-public-site-theme')
    expect(shell_standard_source).to include("public-site-theme--")
    expect(shell_luxury_source).to include("public-theme-shell--")
  end
end

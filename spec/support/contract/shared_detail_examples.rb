RSpec.shared_examples "contrato do detalhe público" do
  it "expõe as regiões canônicas no detalhe padrão" do
    expect(detail_standard_source).to include("public-theme-property-gallery--default")
    expect(detail_standard_source).to include("public-theme-property-info--default")
    expect(detail_standard_source).to include("public-theme-property-contact-box--default")
    expect(detail_standard_source).to include("public-theme-property-map--default")
  end

  it "expõe as mesmas regiões na variante luxury" do
    expect(detail_luxury_source).to include("public-theme-property-gallery--")
    expect(detail_luxury_source).to include("public-theme-property-info--")
    expect(detail_luxury_source).to include("public-theme-property-contact-box--")
    expect(detail_luxury_source).to include("public-theme-property-map--")
  end
end

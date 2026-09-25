RSpec.shared_examples "contrato do card público" do
  it "expõe redução de venda: anterior, atual, percentual, faixa e CTA com lead" do
    tenant = Tenant.create!(name: "Contrato", slug: "card-contrato")
    property = create(:habitation, tenant: tenant, valor_venda_cents: 990_000_000,
                                               valor_venda_anterior_cents: 1_100_000_000)

    render(card_partial, property: property, variant: card_variant)

    expect(rendered).to include("public-theme-property-card__previous-price")
    expect(rendered).to include("11.000.000")
    expect(rendered).to include("9.900.000")
    expect(rendered).to include("10%")
    expect(rendered).to include("OPORTUNIDADE")
    expect(rendered).to include("Tenho interesse")
    expect(rendered).to include('data-require-lead-form="true"')
    expect(rendered).to include(property.codigo)
    expect(rendered).to include('marketing-tracker-placement-value="property_card"')
    expect(rendered).to include("public-theme-property-card__favorite")
  end

  it "marca locação com redução e sufixo mensal" do
    tenant = Tenant.create!(name: "Contrato", slug: "card-contrato-rent")
    property = create(:habitation, tenant: tenant, valor_venda_cents: 0,
                                               valor_venda_anterior_cents: 0,
                                               valor_locacao_cents: 500_000,
                                               valor_locacao_anterior_cents: 580_000)

    render(card_partial, property: property, variant: card_variant)

    expect(rendered).to include("LOCAÇÃO COM PREÇO REDUZIDO")
    expect(rendered).to include("14%")
    expect(rendered).to include("/mês")
  end

  it "omite redução sem preço anterior maior" do
    tenant = Tenant.create!(name: "Contrato", slug: "card-contrato-cheio")
    property = create(:habitation, tenant: tenant, valor_venda_cents: 990_000_000,
                                               valor_venda_anterior_cents: 0)

    render(card_partial, property: property, variant: card_variant)

    expect(rendered).to include("Valor")
    expect(rendered).not_to include("public-theme-property-card__previous-price")
    expect(rendered).not_to include("public-theme-property-card__opportunity")
    expect(rendered).to include("9.900.000")
  end
end

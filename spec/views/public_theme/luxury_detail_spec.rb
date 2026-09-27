require "rails_helper"

RSpec.describe "public_theme/_luxury_detail_body.html.erb", type: :view do
  let(:tenant) { Tenant.create!(name: "Salute Imóveis", slug: "lux-detail") }

  before do
    # O menu de compartilhar do corretor consulta o admin logado (Devise).
    without_partial_double_verification do
      allow(view).to receive(:current_admin_user).and_return(nil)
      # Botão do simulador no card de preço usa a variante do tema da conta.
      allow(view).to receive(:theme_variant).and_return("salute-luxury")
    end
    assign(:public_map, nil)
    assign(:related_properties, [])
    # O controller entrega o perfil público (simulador de financiamento ligado por padrão).
    assign(:public_site_profile, PublicSiteProfile.new({}, tenant: tenant))
  end

  it "renderiza detalhe luxury com a estrutura de página do tema" do
    habitation = create(:habitation, tenant: tenant, suites_qtd: 2, vagas_qtd: 1)
    assign(:habitation, habitation)

    render("public_theme/luxury_detail_body")

    html = Nokogiri::HTML(rendered)
    expect(rendered).to include("public-theme-property-gallery--salute-luxury")
    expect(html.at_css(".sl-detail__breadcrumb strong").text).to eq(habitation.codigo)
    expect(html.at_css(".sl-detail__headline h1").text.strip).to eq(habitation.display_title)
    expect(html.at_css(".sl-detail__layout .sl-detail__main .sl-detail__info")).to be_present
    description = html.at_css('.sl-detail__description[data-controller="collapsible-text"]')
    expect(description.at_css('[data-collapsible-text-target="content"]')).to be_present
    expect(description.at_css('[data-collapsible-text-target="toggle"]').text.squish).to eq("Ler mais")
    expect(html.at_css(".sl-detail__layout .sl-detail__aside .public-theme-property-contact-box--salute-luxury")).to be_present
    expect(html.at_css(".sl-detail__floating-cta [data-require-lead-form='true']")).to be_present
    expect(view.content_for(:public_shell_class)).to include("sl-detail")
  end

  it "mostra o preço de locação e não duplica os botões de contato" do
    habitation = create(:habitation, tenant: tenant, valor_venda_cents: 0, valor_locacao_cents: 850_000)
    assign(:habitation, habitation)

    render("public_theme/luxury_detail_body")

    html = Nokogiri::HTML(rendered)
    aside = html.at_css(".sl-detail__aside")
    expect(aside.text).to include("8.500")
    expect(aside.text).not_to include("Sob consulta")
    expect(aside.css(".public-habitations-show__cta--whatsapp").size).to eq(1)
    expect(html.css(".sl-detail__mobile-price .public-habitations-show__cta")).to be_empty
  end

  it "mostra empreendimento discreto, imóveis do bairro e links por cidade" do
    development = create(:habitation, tenant: tenant, codigo: "LUX-DEV", tipo: "Empreendimento", categoria: "Apartamento",
                                      nome_empreendimento: "Torre Reservada", infra_estrutura: ["Piscina"])
    habitation = create(:habitation, tenant: tenant, codigo_empreendimento: development.codigo)
    neighbor = create(:habitation, tenant: tenant)
    assign(:habitation, habitation)
    assign(:property_development, development)
    assign(:neighborhood_properties, [neighbor])
    assign(:city_link_groups, [{ label: "Balneário Camboriú", value: "Balneário Camboriú", count: 10,
                                 neighborhoods: [{ label: "Centro", value: "Centro - Balneário Camboriú", count: 5 }] }])

    render("public_theme/luxury_detail_body")

    html = Nokogiri::HTML(rendered)
    expect(html.at_css(".public-theme-property-development--salute-luxury")).to be_present
    expect(rendered).not_to include("Torre Reservada")
    expect(html.css(".sl-detail__similar h2").map { _1.text.strip }).to include(a_string_starting_with("Mais imóveis em"))
    expect(html.at_css(".public-theme-city-links--salute-luxury a[href*='Centro']")).to be_present
  end
end

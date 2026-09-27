require "rails_helper"

# Contrato de todos os temas do site público (docs/public-theme-contract.md).
# Percorre Tenant::PUBLIC_SITE_THEMES — que lista as folhas de
# public_site_themes/ —, então um tema criado depois entra aqui sozinho e
# precisa emitir os mesmos componentes que os atuais. Falhou num tema só?
# O componente foi feito para um tema e esqueceu os outros.
RSpec.describe "Contrato dos temas públicos", type: :request do
  let(:tenant) { Tenant.default }
  let(:address) { { logradouro: "Av. Brasil", numero: "1", bairro: "Centro", cidade: "Itajaí", uf: "SC" } }

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Rails.cache.clear
    HomeSetting.instance(tenant:).update!(search_filter_display_mode: "floating", mobile_search_filter_display_mode: "floating")
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  def html = Nokogiri::HTML(response.body)

  Tenant::PUBLIC_SITE_THEMES.each do |theme_key, theme|
    variant = theme[:variant].presence || "default"

    context "tema #{theme_key} (variante #{variant})" do
      before { tenant.update_columns(public_site_theme: theme_key) }

      it "home: folha do tema, menu, filtro global e seções com o cabeçalho do contrato" do
        create_list(:habitation, 2, tenant:, exibir_no_site_flag: true, address_attributes: address)
        section = tenant.home_sections.create!(section_type: :featured_properties, title: "Destaques", active: true,
                                               order_position: 1, property_filters: { "exibir_no_site" => "1" })

        get root_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("public_site_themes/#{theme_key}")
        expect(html.at_css(".public-theme-navigation-overlay--#{variant}[data-controller='navigation-overlay']")).to be_present
        expect(html.at_css(".public-theme-filter-drawer--#{variant}")).to be_present
        expect(html.at_css(".public-theme-filter-fab--#{variant}")).to be_present
        block = html.at_css("[data-public-home-section='#{section.id}']")
        expect(block.at_css(".public-theme-section__head--#{variant} .public-theme-section__title").text.strip).to eq("Destaques")
        expect(block.at_css(".public-theme-section__cta--#{variant}")).to be_present
        expect(block.css("[data-property-id]")).to be_present
      end

      it "página do imóvel: bloco do empreendimento, bairro, cidades e mapa na variante" do
        development = create(:habitation, codigo: "DEV-#{theme_key}", tipo: "Empreendimento", categoria: "Apartamento",
                                          nome_empreendimento: "Residencial Contrato", address_attributes: address)
        unit = create(:habitation, slug: "unidade-#{theme_key.dasherize}", categoria: "Apartamento",
                                   codigo_empreendimento: development.codigo, address_attributes: address)
        create(:habitation, slug: "vizinho-#{theme_key.dasherize}", address_attributes: address)

        get habitation_path(unit)

        expect(response).to have_http_status(:ok)
        expect(html.at_css(".public-theme-property-development--#{variant}")).to be_present
        expect(html.at_css(".public-theme-city-links--#{variant}")).to be_present
        expect(html.at_css(".public-theme-property-map--#{variant}")).to be_present
        expect(html.at_css(".public-theme-navigation-overlay--#{variant}")).to be_present
      end

      it "simulador de financiamento: página e bloco do imóvel à venda na variante" do
        sale = create(:habitation, tenant:, exibir_no_site_flag: true, status: "Venda", valor_venda_cents: 700_000_00,
                                   slug: "venda-#{theme_key.dasherize}", address_attributes: address)

        get simulador_path
        expect(response).to have_http_status(:ok)
        expect(html.at_css(".public-theme-page-head--#{variant}")).to be_present
        expect(html.at_css(".public-theme-financing-simulator--#{variant}[data-controller='financing-simulator']")).to be_present

        get habitation_path(sale)
        expect(html.at_css(".public-theme-financing-simulator--#{variant}.public-theme-financing-simulator--property")).to be_present
      end

      it "empreendimentos: cabeçalho de página, card compartilhado e paginação do tema" do
        development = create(:habitation, tipo: "Empreendimento", nome_empreendimento: "Torre Contrato", address_attributes: address)
        create(:habitation, codigo_empreendimento: development.codigo, address_attributes: address)

        get empreendimentos_path

        expect(response).to have_http_status(:ok)
        expect(html.at_css(".public-theme-developments--#{variant} .public-theme-page-head--#{variant}")).to be_present
        expect(html.at_css(".public-theme-dev-card")).to be_present
        expect(html.at_css(".public-theme-navigation-overlay--#{variant}")).to be_present
      end
    end
  end

  it "o CSS da variante padrão fica escopado (carrega junto de todos os temas)" do
    # application.css entra em todas as páginas; regra sem --default vazaria
    # para o luxury. Só a transição comum do menu é compartilhada de propósito.
    %w[_public_theme_navigation_overlay _public_global_search_drawer _public_theme_listing _public_theme_home _public_theme_financing_simulator].each do |file|
      css = Rails.root.join("app/assets/stylesheets/components/#{file}.scss").read
      component_rules = css.scan(/^\.public-theme-(?:filter-drawer|filter-fab|page-head|developments|home-section|section__head|section__cta|navigation-overlay--|financing-)[\w-]*[^{]*\{/)
      expect(component_rules.reject { _1.include?("--default") }).to be_empty, "#{file}: #{component_rules.reject { _1.include?('--default') }.first}"
    end
  end
end

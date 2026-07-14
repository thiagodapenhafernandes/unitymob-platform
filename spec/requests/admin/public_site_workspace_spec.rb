require "rails_helper"

RSpec.describe "Admin public site workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "padroniza as listagens de conteúdo público" do
    [admin_landing_pages_path, admin_banners_path, admin_home_sections_path, admin_seo_redirects_path].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
      expect(response.body).to include("public-site-workspace"), path
      expect(response.body).to include("ax-workspace-heading"), path
    end
  end

  it "consolida listagem, cadastro, edicao e detalhe de banners sem vazar outro tenant" do
    banner = admin.tenant.banners.create!(
      title: "Banner da conta #{SecureRandom.hex(3)}",
      positions: %w[home_after_hero search_results],
      display_order: 1,
      active: true
    )
    other_tenant = Tenant.create!(name: "Outra conta de banners #{SecureRandom.hex(3)}", slug: "outros-banners-#{SecureRandom.hex(4)}")
    foreign_banner = other_tenant.banners.create!(title: "Banner externo #{SecureRandom.hex(3)}", positions: ["sidebar"], display_order: 2)

    get admin_banners_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("table.ax-table caption").text).to include("Banners configurados")
    expect(document.css('table.ax-table th[scope="col"]').size).to eq(6)
    expect(document.at_css(%([aria-label="Ver banner #{banner.title}"]))).to be_present
    expect(document.at_css(%([aria-label="Editar banner #{banner.title}"]))).to be_present
    expect(document.at_css(%([aria-label="Remover banner #{banner.title}"]))).to be_present
    expect(response.body).to include(banner.title)
    expect(response.body).not_to include(foreign_banner.title)

    get new_admin_banner_path
    expect(response).to have_http_status(:ok)
    new_form = Nokogiri::HTML(response.body)
    expect(new_form.css('.ax-chip-grid input[name="banner[positions][]"]').size).to eq(Banner::POSITIONS.size)
    expect(new_form.css('input[type="hidden"][name="banner[positions][]"]')).to be_empty
    expect(new_form.at_css(".ax-form-actions--static")).to be_present
    expect(new_form.at_css(".ax-number-field #banner_display_order")).to be_present

    get edit_admin_banner_path(banner)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Editar banner", banner.title, "Salvar alterações")

    get admin_banner_path(banner)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pré-visualização do banner", "Dados detalhados", banner.title)
  end

  it "padroniza os editores estruturais e remove previews explicativos" do
    get edit_admin_home_setting_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("public-site-workspace")
    expect(response.body).not_to include("<strong>Dica:</strong>")

    get edit_admin_contact_setting_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("public-site-workspace")
    expect(response.body).not_to include("Preview dos Links")

    get edit_admin_footer_setting_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("public-site-workspace")

    get edit_admin_public_site_profile_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pilares institucionais")
    expect(response.body).to include("Links úteis")
  end

  it "organiza e salva o rodapé somente no tenant autenticado" do
    other_tenant = Tenant.create!(name: "Outro rodapé #{SecureRandom.hex(3)}", slug: "outro-rodape-#{SecureRandom.hex(4)}")
    other_setting = FooterSetting.instance(tenant: other_tenant)
    other_setting.update!(about_title: "Rodapé externo")

    get edit_admin_footer_setting_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    tabs = html.css("#footerTabs [role='tab']")
    expect(tabs.size).to eq(4)
    expect(tabs.map { |tab| [tab["aria-controls"], tab["aria-selected"], tab["tabindex"]] }).to eq([
      ["general", "true", "0"],
      ["links", "false", "-1"],
      ["stores", "false", "-1"],
      ["social", "false", "-1"]
    ])
    expect(html.css(".tab-content, .tab-pane")).to be_empty
    expect(html.at_css('#links[hidden][aria-labelledby="links-tab"]')).to be_present
    expect(html.at_css('input[type="tel"][name="footer_setting[whatsapp]"][data-controller="phone-input"]')).to be_present
    expect(html.at_css('input[name*="[footer_stores_attributes]"][name$="[name]"]')).to be_present
    expect(response.body).not_to include("Rodapé externo")

    patch admin_footer_setting_path, params: {
      footer_setting: {
        about_title: "Rodapé da conta atual",
        about_text: "Descrição atualizada",
        whatsapp: "(47) 99999-1111",
        email: "rodape@example.com"
      }
    }

    expect(response).to redirect_to(edit_admin_footer_setting_path)
    expect(FooterSetting.instance(tenant: admin.tenant)).to have_attributes(
      about_title: "Rodapé da conta atual",
      about_text: "Descrição atualizada",
      whatsapp: "5547999991111",
      email: "rodape@example.com"
    )
    expect(other_setting.reload.about_title).to eq("Rodapé externo")
  end

  it "inicializa a previa do overlay da Home pelos campos sem estilo inline" do
    setting = HomeSetting.instance(tenant: admin.tenant)
    setting.update!(overlay_color: "#123456", overlay_opacity: 0.4)
    setting.hero_slides.destroy_all
    setting.hero_background_desktop.attach(
      io: StringIO.new("image"),
      filename: "hero-legado.jpg",
      content_type: "image/jpeg"
    )

    get edit_admin_home_setting_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    overlay = html.at_css("#hero-overlay-preview[data-home-settings-preview-target='overlayPreview']")
    expect(overlay).to be_present
    expect(overlay["style"]).to be_nil
    expect(html.at_css("#input-overlay-color-text")["value"]).to eq("#123456")
    expect(html.at_css("#input-overlay-opacity")["value"]).to eq("0.4")
    color_control = html.at_css('.ax-color-control[data-controller~="ax-color-pair"]')
    expect(color_control).to be_present
    expect(color_control.at_css('[data-ax-color-pair-target="swatch"]')["id"]).not_to eq(color_control.at_css('[data-ax-color-pair-target="text"]')["id"])
    expect(color_control.css("[oninput]")).to be_empty
  end

  it "organiza as tabs, midias vazias e acoes da Home com contratos compartilhados" do
    setting = HomeSetting.instance(tenant: admin.tenant)
    setting.hero_slides.destroy_all
    setting.hero_background_desktop.purge
    setting.hero_background_mobile.purge

    get edit_admin_home_setting_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    tabs = html.css("#homeSettingsTabs [role='tab']")
    expect(tabs.size).to eq(3)
    expect(tabs.map { |tab| [tab["aria-controls"], tab["aria-selected"], tab["tabindex"]] }).to eq([
      ["hero", "true", "0"],
      ["cta", "false", "-1"],
      ["sections", "false", "-1"]
    ])
    expect(html.at_css("#cta[hidden][aria-labelledby='cta-tab']")).to be_present
    expect(html.at_css("#sections[hidden][aria-labelledby='sections-tab']")).to be_present
    expect(html.css(".ax-operational-panel").size).to eq(6)
    expect(html.css(".ax-field-group").size).to eq(6)
    expect(html.at_css('input[type="file"][name="home_setting[hero_slide_images][]"][multiple]')).to be_present
    expect(html.at_css('#input-overlay-opacity[type="number"]')).to be_present
    expect(html.css(".ax-number-field .ax-field__hint").map(&:text)).to include("Use um valor entre 0,0 e 1,0.")
    expect(html.css(".tab-content, .tab-pane, .card, .form-control, .alert-link")).to be_empty
    expect(response.body).to include("Nenhuma imagem desktop carregada", "Nenhuma imagem mobile carregada", "ax-sticky-action-footer")
    expect(response.body).not_to include("bg-white", "bg-light")
  end

  it "salva a Home somente no tenant autenticado" do
    other_tenant = Tenant.create!(name: "Outra Home #{SecureRandom.hex(3)}", slug: "outra-home-#{SecureRandom.hex(3)}")
    other_setting = HomeSetting.instance(tenant: other_tenant)
    other_setting.update!(hero_title: "Hero de outra conta")

    patch admin_home_setting_path, params: {
      home_setting: { hero_title: "Hero exclusivo da conta atual" }
    }

    expect(response).to redirect_to(edit_admin_home_setting_path)
    expect(HomeSetting.instance(tenant: admin.tenant).reload.hero_title).to eq("Hero exclusivo da conta atual")
    expect(other_setting.reload.hero_title).to eq("Hero de outra conta")
  end

  it "bloqueia acesso direto de usuario sem permissao de marketing" do
    sign_out admin
    user = create(:admin_user)
    expect(user.can?(:manage, :marketing)).to be(false)
    sign_in user

    get edit_admin_home_setting_path

    expect(response).to redirect_to(admin_root_path)
  end

  it "não oferece localidades de outro tenant no editor de landing pages" do
    other_tenant = Tenant.create!(name: "Outra conta", slug: "outra-#{SecureRandom.hex(4)}")
    create(:habitation, tenant: other_tenant, cidade: "Cidade Exclusiva Outro Tenant", exibir_no_site_flag: true)

    get new_admin_landing_page_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Cidade Exclusiva Outro Tenant")
    expect(response.body).to include("Conteúdo e SEO", "Filtros de imóveis", "Resumo do conjunto")
    expect(response.body).to include('data-controller="property-page-preview"', 'data-property-page-preview-target="count"')
    expect(response.body.scan('name="landing_page[filter_params][characteristics][]"').size).to eq(20)
    expect(response.body).not_to include('type="hidden" name="landing_page[filter_params][characteristics][]"')
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('.ax-field input[name="landing_page[title]"]')).to be_present
    expect(html.at_css('.ax-input-group input[name="landing_page[slug]"]')).to be_present
    expect(html.css('select.ax-autocomplete-select[multiple]').map { |select| select["name"] }).to contain_exactly(
      "landing_page[filter_params][category][]",
      "landing_page[filter_params][city][]",
      "landing_page[filter_params][neighborhood][]"
    )
    expect(html.at_css('.ax-measure-field input[name="landing_page[filter_params][min_area]"]')).to be_present
    expect(html.at_css(".ax-form-actions--static")).to be_present
    expect(html.css(".form-group, .form-control, .tab-pane, .card")).to be_empty
  end

  it "cria landing page somente no tenant autenticado e preserva os filtros" do
    other_tenant = Tenant.create!(name: "Outra conta de landing pages #{SecureRandom.hex(3)}", slug: "outra-landing-#{SecureRandom.hex(4)}")
    foreign_page = other_tenant.landing_pages.create!(title: "Landing externa", slug: "landing-externa", active: true)
    slug = "apartamentos-#{SecureRandom.hex(4)}"

    expect do
      post admin_landing_pages_path, params: {
        landing_page: {
          title: "Apartamentos selecionados",
          slug:,
          meta_title: "Apartamentos para comprar",
          meta_description: "Seleção exclusiva de apartamentos",
          description: "Introdução pública",
          content: "Conteúdo de rodapé",
          active: "1",
          filter_params: {
            category: ["Apartamento"],
            city: ["Balneário Camboriú"],
            neighborhood: ["Centro"],
            transaction_type: "venda",
            target_price: "1500000",
            min_area: "80",
            min_bedrooms: "2",
            min_suites: "1",
            min_parking: "1",
            characteristics: %w[frente_mar piscina]
          }
        }
      }
    end.to change { admin.tenant.landing_pages.count }.by(1)
      .and change { other_tenant.landing_pages.count }.by(0)

    expect(response).to redirect_to(admin_landing_pages_path)
    page = admin.tenant.landing_pages.find_by!(slug:)
    expect(page).to have_attributes(title: "Apartamentos selecionados", active: true)
    expect(page.filter_params).to include(
      "category" => ["Apartamento"],
      "city" => ["Balneário Camboriú"],
      "neighborhood" => ["Centro"],
      "transaction_type" => "venda",
      "characteristics" => %w[frente_mar piscina]
    )
    expect(foreign_page.reload.title).to eq("Landing externa")
  end

  it "limita a prévia da landing page aos imóveis públicos do tenant autenticado" do
    category = "Categoria exclusiva #{SecureRandom.hex(3)}"
    create(:habitation, tenant: admin.tenant, categoria: category, valor_venda_cents: 125_000_000)
    other_tenant = Tenant.create!(name: "Outra prévia #{SecureRandom.hex(3)}", slug: "outra-previa-#{SecureRandom.hex(4)}")
    create(:habitation, tenant: other_tenant, categoria: category, valor_venda_cents: 900_000_000)

    get preview_admin_landing_pages_path, params: { category: [category] }, as: :json

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload["count"]).to eq(1)
    expect(payload.dig("metrics", "distribution")).to eq(category => 1)
    expect(payload.dig("metrics", "avg_price")).to include("1.250.000")
  end

  it "renderiza detalhe e formularios das secoes da Home com componentes compartilhados" do
    section = admin.tenant.home_sections.create!(section_type: :services, title: "Serviços especiais", active: true)
    section.home_section_items.create!(title: "Avaliação", description: "Avaliação especializada", active: true)
    filter_section = admin.tenant.home_sections.create!(section_type: :featured_properties, title: "Imóveis em destaque", active: true)

    get admin_home_section_path(section)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-record-list", "ax-record-item", "Avaliação especializada")
    expect(Nokogiri::HTML(response.body).css(".public-site-workspace [style]")).to be_empty

    get edit_admin_home_section_path(filter_section)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-chip-grid", "ax-toggle-chip")
    expect(response.body.scan('name="home_section[property_filters]').size).to eq(HomeSection::PROPERTY_FILTER_OPTIONS.size)
    expect(Nokogiri::HTML(response.body).css(".ax-chip-grid [style]")).to be_empty

    get new_admin_home_section_home_section_item_path(section)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Novo Item", "home_section_item[icon]")
  end
end

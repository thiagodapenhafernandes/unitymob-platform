require "rails_helper"

RSpec.describe "Admin::HomeSections formulário", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  it "mantém a organização de campos e agrupa os filtros em grupos coloridos" do
    get new_admin_home_section_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("select[name='home_section[content_kind]']").css("option").map { |option| option["value"] }).to eq(%w[properties videos blog cta])
    expect(html.at_css("input[name='home_section[title]']")).to be_present
    expect(html.at_css("textarea[name='home_section[subtitle]']")).to be_present
    expect(html.at_css("input[type='checkbox'][name='home_section[active]']")).to be_present
    expect(html.css(".ax-studio-group").size).to eq(3)
    expect(html.css("[data-chip-section]").size).to eq(HomeSection::PROPERTY_FILTER_GROUPS.size)
    expect(html.css("input[name^='home_section[property_filters]'].ax-toggle-chip__input").size).to eq(HomeSection::PROPERTY_FILTER_OPTIONS.size)
    expect(html.at_css(".ax-studio-savebar")).to be_present
    expect(html.at_css(".hs-recipe")).to be_nil
    expect(html.at_css("[data-home-section-preview-target='preview']")).to be_present
    expect(html.at_css("[data-controller~='home-section-preview']")["data-home-section-preview-preview-url-value"]).to eq(preview_admin_home_sections_path)
  end

  describe "imóveis específicos" do
    let!(:valid_sale) { create(:habitation, tenant: admin.tenant, titulo_anuncio: "Venda válida", exibir_no_site_flag: true, status: "Venda", valor_venda_cents: 500_000_00, valor_locacao_cents: 0) }
    let!(:valid_both) { create(:habitation, tenant: admin.tenant, titulo_anuncio: "Venda e locação válida", exibir_no_site_flag: true, status: "Venda e Aluguel", valor_venda_cents: 500_000_00, valor_locacao_cents: 3_000_00) }
    let!(:sold) { create(:habitation, tenant: admin.tenant, titulo_anuncio: "Suspenso", exibir_no_site_flag: true, status: "Suspenso", motivo_suspensao: "Teste") }
    let!(:hidden) { create(:habitation, tenant: admin.tenant, titulo_anuncio: "Fora do site", exibir_no_site_flag: false, status: "Venda") }
    let!(:development) { create(:habitation, tenant: admin.tenant, titulo_anuncio: "Um empreendimento", tipo: "Empreendimento", exibir_no_site_flag: true, status: "Venda") }

    def option_ids
      Nokogiri::HTML(response.body).css("select[name='home_section[property_filters][selected_property_ids][]'] option").map { |option| option["value"].to_i }
    end

    it "lista só imóveis publicados como venda, locação ou venda e locação (nada vendido, fora do site ou empreendimento)" do
      get new_admin_home_section_path

      expect(option_ids).to include(valid_sale.id, valid_both.id)
      expect(option_ids).not_to include(sold.id, hidden.id, development.id)
    end

    it "mostra no rótulo se é venda, locação ou venda e locação" do
      get new_admin_home_section_path

      labels = Nokogiri::HTML(response.body).css("select[name='home_section[property_filters][selected_property_ids][]'] option").to_h { |option| [option["value"].to_i, option.text] }
      expect(labels[valid_sale.id]).to end_with("Venda")
      expect(labels[valid_both.id]).to end_with("Venda e Locação")
    end

    it "não grava imóvel inelegível mesmo que o id seja enviado à mão" do
      post admin_home_sections_path, params: { home_section: { content_kind: "properties", title: "Curada", active: "1", property_filters: { selected_property_ids: [valid_sale.id, sold.id, development.id].map(&:to_s) } } }

      expect(admin.tenant.home_sections.order(:created_at).last.selected_property_ids).to eq([valid_sale.id])
    end
  end

  it "cria uma chamada para contato: tipo cta_contact, sem filtros de imóvel" do
    post admin_home_sections_path, params: { home_section: { content_kind: "cta", title: "Vamos conversar?", active: "1", property_filters: { frente_mar: "1" } } }

    section = admin.tenant.home_sections.order(:created_at).last
    expect(section).to be_cta_contact
    expect(section.property_filters).to eq({})
  end

  it "abre seção de vídeos com curadoria específica e sem filtros automáticos visíveis" do
    with_video = create(:habitation, tenant: admin.tenant, titulo_anuncio: "Com tour em vídeo", exibir_no_site_flag: true, videos: ["https://youtu.be/abc123"])
    without_video = create(:habitation, tenant: admin.tenant, titulo_anuncio: "Sem vídeo", exibir_no_site_flag: true)
    section = admin.tenant.home_sections.create!(section_type: :featured_videos, title: "Vídeos em destaque", active: true)

    get edit_admin_home_section_path(section)

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("select[name='home_section[content_kind]'] option[selected]")["value"]).to eq("videos")
    video_panel = html.at_css("[data-conditional-reveal-values='videos']")
    property_panel = html.at_css("[data-conditional-reveal-values='properties|custom']")
    expect(video_panel).to be_present
    expect(video_panel.has_attribute?("hidden")).to be(false)
    expect(video_panel.text).to include("Vitrine de vídeos", "YouTube", "Vimeo", "Spaces", "chips de cidade")
    expect(video_panel.text).to include("Vídeos manuais", "Instagram", "Upload Spaces")
    expect(video_panel.at_css("[data-controller='nested-form']")).to be_present
    expect(video_panel.at_css("template [data-controller='home-section-video-item']")).to be_present
    expect(video_panel.at_css("template [data-home-section-video-item-target='externalField']")).to be_present
    expect(video_panel.at_css("template [data-home-section-video-item-target='uploadField']")).to be_present
    expect(video_panel.at_css("template [data-home-section-video-item-target='media']")).to be_present
    expect(video_panel.at_css("template input[name*='[source_url]']")).to be_present
    expect(video_panel.at_css("template input[type='file'][name*='[video_file]']")).to be_present
    expect(property_panel.has_attribute?("hidden")).to be(true)
    expect(video_panel.css("[data-chip-section]")).to be_empty
    expect(video_panel.css("select[name='home_section[property_filters][selected_property_ids][]'] option").map { |option| option["value"] }).to include(with_video.id.to_s)
    expect(video_panel.css("select[name='home_section[property_filters][selected_property_ids][]'] option").map { |option| option["value"] }).not_to include(without_video.id.to_s)
  end

  it "salva vídeos manuais com URL externa e metadados da vitrine" do
    post admin_home_sections_path, params: {
      home_section: {
        content_kind: "videos",
        title: "Vídeos especiais",
        active: "1",
        home_section_items_attributes: {
          "0" => {
            source_type: "external",
            source_url: "https://www.instagram.com/reel/ABC123/",
            title: "Andar alto frente mar",
            location: "Balneário Camboriú · Barra Sul",
            price_label: "R$ 13.400.000",
            badges_text: "Pronto para morar, Vista mar",
            active: "1",
            display_order: "1"
          }
        }
      }
    }

    expect(response).to redirect_to(admin_home_sections_path)
    section = admin.tenant.home_sections.order(:created_at).last
    item = section.home_section_items.first
    expect(section).to be_featured_videos
    expect(item.source_type).to eq("external")
    expect(item.source_url).to eq("https://www.instagram.com/reel/ABC123/")
    expect(item.badges).to eq(["Pronto para morar", "Vista mar"])
  end

  it "prévia mostra só os imóveis escolhidos, ignorando filtros que eles não atendem" do
    chosen = create(:habitation, tenant: admin.tenant, titulo_anuncio: "Escolhido a dedo", exibir_no_site_flag: true)

    get preview_admin_home_sections_path, params: { home_section: { content_kind: "properties", title: "Vitrine", active: "1", property_filters: { frente_mar: "1", selected_property_ids: [chosen.id.to_s] } } }

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)
    expect(data).to include("kind" => "properties", "title" => "Vitrine", "active" => true)
    expect(data["manual"]).to eq(1)
    expect(data["count"]).to eq(1)
    expect(data["items"].first["title"]).to eq("Escolhido a dedo")
  end

  it "prévia avisa quando nenhum imóvel atende e para o blog e a chamada" do
    get preview_admin_home_sections_path, params: { home_section: { content_kind: "properties", title: "Vazia", property_filters: { frente_mar: "1" } } }
    expect(JSON.parse(response.body)["warning"]).to include("Nenhum imóvel")

    get preview_admin_home_sections_path, params: { home_section: { content_kind: "blog", title: "Blog" } }
    expect(JSON.parse(response.body)).to include("kind" => "blog")

    get preview_admin_home_sections_path, params: { home_section: { content_kind: "cta", title: "CTA" } }
    expect(JSON.parse(response.body)["buttons"]).to include("Fale Conosco", "WhatsApp")
  end

  it "prévia de vídeos considera URL manual mesmo sem imóveis selecionados" do
    get preview_admin_home_sections_path, params: {
      home_section: {
        content_kind: "videos",
        title: "Vídeos",
        home_section_items_attributes: {
          "0" => { source_type: "external", source_url: "https://youtu.be/_2SaTVBZn0o", title: "Vista panorâmica", location: "Itapema", price_label: "R$ 2.000.000", badges_text: "Frente mar", active: "1" },
          "1" => { source_type: "external", source_url: "https://youtu.be/_2SaTVBZn0o", title: "Segundo vídeo", active: "1" },
          "2" => { source_type: "external", source_url: "https://youtu.be/_2SaTVBZn0o", title: "Terceiro vídeo", active: "1" },
          "3" => { source_type: "external", source_url: "https://youtu.be/_2SaTVBZn0o", title: "Quarto vídeo", active: "1" }
        }
      }
    }

    data = JSON.parse(response.body)
    expect(data["kind"]).to eq("property_videos")
    expect(data["count"]).to eq(4)
    expect(data["items"].size).to eq(3)
    expect(data["warning"]).to be_nil
    expect(data["items"].first).to include("title" => "Vista panorâmica", "price" => "R$ 2.000.000", "badges" => ["Frente mar"])
  end

  # Regressão: a prévia monta uma seção nova e descartável; mandar o id de um item já
  # persistido (editando uma seção existente) fazia o Rails tentar achá-lo na associação
  # vazia do objeto novo e estourar RecordNotFound ("Prévia indisponível" na tela).
  it "prévia de vídeos funciona ao editar uma seção com item já salvo" do
    section = admin.tenant.home_sections.create!(section_type: "featured_videos", title: "Vídeos", active: true)
    saved_item = section.home_section_items.create!(
      source_type: "external", source_url: "https://youtu.be/_2SaTVBZn0o", title: "Já salvo", active: true, display_order: 1
    )

    get preview_admin_home_sections_path, params: {
      home_section: {
        content_kind: "videos",
        title: "Vídeos",
        home_section_items_attributes: {
          "0" => { id: saved_item.id.to_s, source_type: "external", source_url: "https://youtu.be/_2SaTVBZn0o", title: "Já salvo", active: "1" },
          "1" => { source_type: "external", source_url: "https://youtu.be/_2SaTVBZn0o", title: "Novo vídeo", active: "1" }
        }
      }
    }

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)
    expect(data["kind"]).to eq("property_videos")
    expect(data["items"].map { |item| item["title"] }).to include("Já salvo", "Novo vídeo")
  end

  it "todo filtro do catálogo aparece em exatamente um grupo" do
    grouped = HomeSection::PROPERTY_FILTER_GROUPS.flat_map { |group| group[:keys] }

    expect(grouped).to eq(grouped.uniq)
    expect(grouped - HomeSection::PROPERTY_FILTER_OPTIONS.keys).to be_empty
  end

  it "ao editar uma seção de blog, abre em Blog com a curadoria escondida" do
    section = admin.tenant.home_sections.create!(section_type: :blog, title: "Blog", active: true)

    get edit_admin_home_section_path(section)

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("select[name='home_section[content_kind]'] option[selected]")["value"]).to eq("blog")
    expect(html.at_css("[data-conditional-reveal-target='panel']").has_attribute?("hidden")).to be(true)
  end

  it "continua salvando o mesmo contrato de parâmetros" do
    post admin_home_sections_path, params: { home_section: { content_kind: "properties", title: "Frente mar", active: "1", property_filters: { frente_mar: "1", venda: "1" } } }

    section = admin.tenant.home_sections.order(:created_at).last
    expect(response).to redirect_to(admin_home_sections_path)
    expect(section.title).to eq("Frente mar")
    expect(section.property_filter_enabled?("frente_mar")).to be(true)
  end

  # Regressão: a prévia (segundo plano, a cada digitação) chegou a derrubar login/impersonação porque o CSRF inválido
  # aciona reset_session. Sendo GET, não passa por essa verificação e nunca mexe na sessão.
  it "prévia não exige token CSRF e não derruba a sessão" do
    ActionController::Base.allow_forgery_protection = true

    get preview_admin_home_sections_path, params: { home_section: { content_kind: "blog", title: "Blog" } }, headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)

    get admin_home_sections_path
    expect(response).to have_http_status(:ok)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end

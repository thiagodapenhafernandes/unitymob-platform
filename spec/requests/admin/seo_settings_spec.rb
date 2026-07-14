require "rails_helper"

RSpec.describe "Admin::SeoSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "seo-settings-#{SecureRandom.hex(8)}@salute.test") }
  let!(:seo_setting) do
    SeoSetting.create!(
      page_name: "imoveis:seo-settings-list",
      canonical_key: "imoveis:seo-settings-list",
      page_type: "property_listing",
      meta_title: "Buscar imóveis",
      meta_description: "Listagem pública de imóveis",
      canonical_path: "/imoveis",
      access_count: 10,
      seo_score: 88,
      active: true,
      apply_to_public: true,
      robots_index: true,
      ai_insights: "Priorize bairros centrais.\nRevise títulos duplicados."
    )
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o cadastro com o cabeçalho compartilhado" do
    get new_admin_seo_setting_path

    expect(response).to have_http_status(:ok)
    header = Nokogiri::HTML(response.body).at_css(".ax-page-head")
    expect(header.at_css(".ax-page-title").text.squish).to eq("Novo SEO")
    expect(header.at_css(".ax-page-title .bi-search[aria-hidden='true']")).to be_present
    expect(header.at_css(".ax-page-subtitle").text.squish).to eq("Crie uma configuração técnica manual.")
  end

  it "renderiza o inventário SEO com componentes operacionais" do
    get admin_seo_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Páginas SEO")
    expect(response.body).to include("ax-workspace-heading")
    expect(response.body).to include("ax-metric-card")
    expect(response.body).to include("Páginas monitoradas")
    expect(response.body).to include("Busca de imóveis")
    expect(response.body).to include("Estratégia IA")
    expect(response.body).not_to include("Seo settings")
    strategy_modal = Nokogiri::HTML(response.body).at_css("#seoStrategyModal")
    expect(strategy_modal.at_css(".ax-quick-modal__title-icon")).to be_present
    expect(strategy_modal.css("[style]")).to be_empty
    progress_bars = Nokogiri::HTML(response.body).css(".ax-metric-card progress.ax-progress__bar")
    expect(progress_bars).not_to be_empty
    expect(progress_bars).to all(satisfy { |bar| bar["max"] == "100" && bar["style"].nil? })
  end

  it "renderiza a edição com painéis operacionais e toggles compartilhados" do
    get edit_admin_seo_setting_path(seo_setting)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Identificação técnica")
    expect(response.body).to include("Snippet para buscadores")
    expect(response.body).to include("Controle público")
    expect(response.body).to include("ax-operational-panel")
    expect(response.body).to include("ax-toggle-chip")
    expect(response.body).to include("data-checked=")
    expect(response.body).to include("ax-sticky-action-footer")
    expect(response.body).not_to include("custom-checkbox-card")
    document = Nokogiri::HTML(response.body)
    insights = document.at_css(".ax-inline-notice__content--multiline")
    expect(insights.text).to include("Priorize bairros centrais", "Revise títulos duplicados")
    expect(insights["style"]).to be_nil
    expect(document.at_css('label.seo-editor-field-head[for="seo_setting_meta_title"] [data-seo-count="title"]')).to be_present
    expect(document.at_css('textarea[name="seo_setting[meta_description]"][data-seo-field="description"]')).to be_present
    expect(document.at_css('input[type="file"][name="seo_setting[og_image_file]"]')).to be_present
  end

  it "atualiza metadados e flags pelo formulário compartilhado" do
    patch admin_seo_setting_path(seo_setting), params: {
      seo_setting: {
        meta_title: "Título SEO atualizado",
        meta_description: "Descrição SEO atualizada",
        focus_keyword_list: "imóveis, centro",
        robots_index: "1",
        robots_follow: "0"
      }
    }

    expect(response).to redirect_to(edit_admin_seo_setting_path(seo_setting))
    seo_setting.reload
    expect(seo_setting).to have_attributes(
      meta_title: "Título SEO atualizado",
      meta_description: "Descrição SEO atualizada",
      robots_index: true,
      robots_follow: false
    )
    expect(seo_setting.focus_keywords.pluck(:keyword)).to contain_exactly("imóveis", "centro")
  end
end

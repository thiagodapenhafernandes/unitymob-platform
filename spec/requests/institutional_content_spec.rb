require "rails_helper"

RSpec.describe "Conteúdo institucional público", type: :request do
  let(:tenant) { Tenant.default }

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Setting.set("public_site.profile.primary_city", "Balneário Camboriú", tenant: tenant)
    create(:habitation, tenant: tenant, exibir_no_site_flag: true,
      address_attributes: { logradouro: "Avenida Brasil", numero: "1", cidade: "Balneário Camboriú", bairro: "Centro", uf: "SC" })
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
    it "mostra conteúdo e regiões da conta no tema #{theme}, sem placeholders" do
      tenant.update_columns(public_site_theme: theme)
      get sobre_path
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      content = document.at_css(".public-theme-institutional__intro")
      expect(content.text).to include("Sobre a")
      expect(response.body).not_to include("Configure a missão", "Configure a visão", "Configure os valores")
      regions = document.at_css("#regioes-de-atuacao")
      expect(regions.text).to include("Balneário Camboriú", "Centro")
      expect(document.at_css("title").text).to include("Balneário Camboriú")
      expect(document.css("main h1").size).to eq(1)
    end
  end

  it "não divulga cidades de outra conta" do
    other = Tenant.create!(name: "Outra imobiliária", slug: "outra-imobiliaria")
    create(:habitation, tenant: other, exibir_no_site_flag: true,
      address_attributes: { logradouro: "Rua A", cidade: "Cidade Exclusiva", bairro: "Centro", uf: "SC" })
    get sobre_path
    expect(Nokogiri::HTML(response.body).at_css("#regioes-de-atuacao").text).not_to include("Cidade Exclusiva")
  end

  it "preserva os pilares publicados" do
    profile = PublicSiteProfile.current(tenant: tenant)
    profile.institutional_mission = "Atendimento com escuta e respeito"
    expect(profile.save).to eq(true)
    get sobre_path
    expect(response.body).to include("Atendimento com escuta e respeito")
  end

  it "mantém as páginas de relacionamento acessíveis" do
    [parcerias_path, trabalhe_conosco_path, contato_path].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).css("main h1").size).to eq(1)
    end
  end

  it "complementa a busca por cidade sem substituir conteúdo configurado" do
    get habitations_path(city: ["Balneário Camboriú"])
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Encontre seu imóvel em Balneário Camboriú", "Imóveis em Centro, Balneário Camboriú")
    tenant.seo_settings.order(:id).last.update!(intro_text: "Texto editorial da imobiliária.", active: true, apply_to_public: true)
    Rails.cache.clear
    get habitations_path(city: ["Balneário Camboriú"])
    expect(response.body).to include("Texto editorial da imobiliária.")
    expect(response.body).not_to include("Encontre seu imóvel em Balneário Camboriú")
  end
end

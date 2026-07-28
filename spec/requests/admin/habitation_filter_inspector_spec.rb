require "rails_helper"

RSpec.describe "Admin habitation filter inspector", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  def default_agent_profile
    admin.tenant.profiles.find_by!(key: "agent").tap do |profile|
      profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    end
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o inspector em um turbo frame separado" do
    create(:habitation, bairro_comercial: "Centro")

    get filter_inspector_admin_habitations_path, headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('turbo-frame id="admin_habitations_filter_inspector"')
    expect(response.body).to include("Filtros do catálogo")
    expect(response.body).to include('autocomplete="off"')
    expect(response.body).to include('data-turbo-frame="_top"')
    expect(response.body).to include('name="codigo"')
    expect(response.body).to include('name="q"')
    expect(response.body).to include('name="bairro_comercial"')
    expect(response.body).not_to include('name="logradouro"')
    expect(response.body.scan('autocomplete="off"').size).to be >= 6
    expect(response.body).not_to include('name="bairro[]"')
    expect(response.body).to include('multiple="multiple"')
    expect(response.body).to include('data-controller="tom-select"')
    expect(response.body).to include("Centro")
  end

  it "organiza os filtros principais conforme o catálogo compacto" do
    get filter_inspector_admin_habitations_path(q: "praia", min_price: "800000", max_price: "1200000"),
        headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    quick_section = document.css(".ax-filter-section").find { |section| section.text.include?("Filtros rápidos") }

    expect(response.body.index("Filtros rápidos")).to be < response.body.index("Dados")
    expect(response.body).to include("Palavra-chave")
    expect(response.body).to include("Código / Referência")
    expect(response.body).to include("Empreendimento")
    expect(response.body).to include("Corretor")
    expect(response.body).to include("Recorte")
    expect(response.body).to include("Tipo e status")
    expect(response.body).to include("Negociação")
    expect(response.body).to include("Características imóvel")
    expect(response.body).to include("Administrativo")
    expect(document.at_css(".habitations-catalog-price-stack input[name='min_price']")).to be_present
    expect(document.at_css(".habitations-catalog-price-stack input[name='max_price']")).to be_present
    expect(quick_section.to_html).to include('name="q"')
  end

  it "renderiza características internas dentro de características imóvel" do
    get filter_inspector_admin_habitations_path(amenities: ["Adega", "Garden"]),
        headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    amenity_section = document.css(".ax-filter-section").find { |section| section.text.include?("Características imóvel") }

    expect(amenity_section).to be_present
    expect(amenity_section.text).to include("Características internas")
    expect(amenity_section.to_html).to include('name="amenities[]"')
    expect(amenity_section.text).to include("Adega")
    expect(amenity_section.text).to include("Ar-condicionado")
    expect(amenity_section.text).to include("Garden")
    expect(amenity_section.text).to include("Quadra mar")
    expect(response.body.index("Características imóvel")).to be < response.body.index("Administrativo")
  end

  it "deduplica características equivalentes por caixa e acento" do
    tenant = admin.tenant
    ["Piscina coletiva", "Porteiro eletrônico", "Quadra de esportes"].each do |name|
      tenant.attribute_options.find_or_create_by!(context: "habitation", category: "infrastructure", name: name)
    end

    Rails.cache.clear

    get filter_inspector_admin_habitations_path(amenities: ["Porteiro Eletrônico"]),
        headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    amenity_section = document.css(".ax-filter-section").find { |section| section.text.include?("Características imóvel") }
    labels = amenity_section.css(".ax-filter-check").map { |label| label.text.squish }

    expect(labels.grep(/\APiscina coletiva\z/i).size).to eq(1)
    expect(labels.grep(/\APorteiro eletrônico\z/i).size).to eq(1)
    expect(labels.grep(/\AQuadra de esportes\z/i).size).to eq(1)
    expect(amenity_section.at_css('input[name="amenities[]"][checked]')["value"]).to eq("Porteiro eletrônico")
  end

  it "atualiza filtros rápidos e remove opções antigas do bloco rápido" do
    get filter_inspector_admin_habitations_path,
        headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    quick_section = document.css(".ax-filter-section").find { |section| section.text.include?("Filtros rápidos") }

    expect(quick_section.text).to include("Sem mobília", "Diferenciado", "Quadra mar")
    expect(quick_section.text).not_to include("Super Destaque", "Sacada")
  end

  it "oculta filtros administrativos para perfil de corretor" do
    agent = create(:admin_user, profile: default_agent_profile)
    sign_in agent

    get filter_inspector_admin_habitations_path(destaque_web: "1", regiao_foco: "Sim"),
        headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    expect(document.css(".ax-filter-section").map(&:text).join(" ")).not_to include("Administrativo")
    expect(document.at_css('select[name="destaque_web"]')).to be_nil
    expect(document.at_css('select[name="regiao_foco"]')).to be_nil
  end

  it "mantém o inspector pesado fora da primeira resposta da listagem" do
    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin_habitations_filter_inspector"')
    expect(response.body).to include("habitations-inspector-skeleton")
    expect(response.body).not_to include('<form class="habitations-inspector__form"')
  end
end

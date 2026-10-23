require "rails_helper"

RSpec.describe "Link curto de compartilhamento de imóvel", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user) }
  let(:property) { create(:habitation, :unavailable, tenant: admin.tenant) }

  before do
    host! "localhost"
    sign_in admin
    allow_any_instance_of(HabitationsController).to receive(:social_image_url_accessible?).and_return(true)
  end

  it "mantém foto, corretor, validade, canonical e privacidade sem parâmetros técnicos na URL" do
    post share_link_habitation_path(property.id, lookup: "id"), as: :json
    expect(response).to have_http_status(:ok)
    url = URI.parse(response.parsed_body.fetch("url"))
    expect(url.query).to be_nil
    expect(url.path).to match(%r{\A/i/[^/]+/\d+\z})
    sign_out admin

    expect { get url.request_uri }.not_to change(SeoSetting, :count)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('meta[property="og:image"]')["content"]).to include("property.jpg")
    expect(html.at_css('meta[property="og:url"]')["content"]).to eq(url.to_s)
    expect(html.at_css('link[rel="canonical"]')["href"]).to include(habitation_path(property))
    expect(response.body).to include(admin.name)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["Referrer-Policy"]).to eq("same-origin")
    expect(property.reload.exibir_no_site_flag).to be(false)
  end

  Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
    it "mantém foto e atribuição no tema #{theme}" do
      admin.tenant.update_columns(public_site_theme: theme)
      link = HabitationShareLink.create!(habitation: property, admin_user: admin)
      sign_out admin
      get shared_habitation_path(token: link.token)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css('meta[property="og:image"]')["content"]).to include("property.jpg")
      expect(response.body.include?(admin.name)).to be(true)
    end
  end

  it "recusa link expirado e token de outra conta" do
    link = HabitationShareLink.create!(habitation: property, admin_user: admin)
    link.update!(expires_at: 1.second.ago)
    get shared_habitation_path(token: link.token)
    expect(response).to have_http_status(:gone)

    other = Tenant.create!(name: "Outra", slug: "share-other-#{SecureRandom.hex(4)}")
    foreign = HabitationShareLink.create!(habitation: create(:habitation, tenant: other), admin_user: create(:admin_user, tenant: other))
    get shared_habitation_path(token: foreign.token)
    expect(response).to have_http_status(:gone)
  end

  it "mantém bloqueio para imóvel suspenso mesmo com token ativo" do
    property.update!(status: "Suspenso", motivo_suspensao: "Fora de pauta")
    link = HabitationShareLink.create!(habitation: property, admin_user: admin)
    get shared_habitation_path(token: link.token)
    expect(response).to redirect_to(habitations_path)
  end

  it "não gera link com foto ausente ou inacessível" do
    property.update_column(:pictures, [])
    post share_link_habitation_path(property.id, lookup: "id"), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(property.habitation_share_links).to be_empty

    property.update_column(:pictures, [{ "url" => "#{Storage::PublicPropertyPhoto.public_base_url}/missing.jpg" }])
    allow_any_instance_of(HabitationsController).to receive(:social_image_url_accessible?).and_return(false)
    post share_link_habitation_path(property.id, lookup: "id"), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(property.habitation_share_links).to be_empty
  end
end

require "rails_helper"

RSpec.describe "Admin::Banners formulário", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  it "organiza por onde exibir, mídia, conteúdo e publicação, com prévia ao lado" do
    get new_admin_banner_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.css(".ax-studio-group").size).to eq(4)
    expect(html.css('.bn-pos input[type="checkbox"][name="banner[positions][]"]').map { |input| input["value"] }).to eq(Banner::POSITIONS.keys)
    expect(html.at_css("input[name='banner[title]']")).to be_present
    expect(html.at_css("input[name='banner[link_url]']")).to be_present
    expect(html.at_css("input[name='banner[link_text]']")).to be_present
    expect(html.at_css("input[type='file'][name='banner[image_desktop]']")).to be_present
    expect(html.at_css("input[type='file'][name='banner[image_mobile]']")).to be_present
    expect(html.at_css("input#banner_active")["checked"]).to be_present # banner novo já nasce ativo (o botão é "Publicar banner")
    expect(html.at_css("#banner_display_order")).to be_present
    expect(html.at_css("[data-controller='banner-preview']")).to be_present
    expect(html.css(".bn-pos__size").map(&:text).join).to include("1440 × 360", "768 × 360")
  end

  it "ao editar um banner inativo, o interruptor continua desligado" do
    banner = admin.tenant.banners.create!(title: "Pausado", positions: ["sidebar"], display_order: 0, active: false)

    get edit_admin_banner_path(banner)

    expect(Nokogiri::HTML(response.body).at_css("input#banner_active")["checked"]).to be_nil
  end

  it "quadros de mídia atualizam ao escolher arquivo (controller compartilhado)" do
    get new_admin_banner_path

    frames = Nokogiri::HTML(response.body).css("article.ax-media-preview[data-controller='ax-media-preview']")
    expect(frames.size).to eq(2)
    expect(frames.first["data-action"]).to include("change->ax-media-preview#pick")
  end

  it "todas as posições têm dica de tamanho" do
    expect(Banner::POSITION_META.keys).to match_array(Banner::POSITIONS.keys)
  end

  it "mostra quem ocupa cada posição (o banner ativo de menor ordem) e ignora inativos e o próprio" do
    admin.tenant.banners.create!(title: "Promo julho", positions: ["home_after_hero"], display_order: 0, active: true)
    admin.tenant.banners.create!(title: "Antigo", positions: ["home_after_hero"], display_order: 3, active: false)
    own = admin.tenant.banners.create!(title: "Meu banner", positions: ["sidebar"], display_order: 0, active: true)

    get edit_admin_banner_path(own)

    html = Nokogiri::HTML(response.body)
    holders = html.css(".bn-pos").to_h { |card| [card.at_css("input")["value"], card.at_css(".bn-pos__holder").text.squish] }
    expect(holders["home_after_hero"]).to eq("Hoje: Promo julho (ordem 0)")
    expect(holders["sidebar"]).to eq("Livre hoje")
    occupancy = JSON.parse(html.at_css("[data-controller='banner-preview']")["data-banner-preview-occupancy-value"])
    expect(occupancy["home_after_hero"].map { |item| item["title"] }).to eq(["Promo julho"])
    expect(occupancy["sidebar"]).to eq([])
  end

  it "não vaza banner de outra conta na ocupação" do
    other = Tenant.create!(name: "Outra #{SecureRandom.hex(3)}", slug: "outra-#{SecureRandom.hex(4)}")
    other.banners.create!(title: "De outra conta", positions: ["home_after_hero"], display_order: 0, active: true)

    get new_admin_banner_path

    expect(response.body).not_to include("De outra conta")
  end

  it "continua salvando o mesmo contrato de parâmetros" do
    post admin_banners_path, params: { banner: { title: "Novo", description: "Sub", link_url: "https://exemplo.com.br", link_text: "Ver", display_order: "2", active: "1", positions: ["sidebar", "home_after_hero"] } }

    expect(response).to redirect_to(admin_banners_path)
    banner = admin.tenant.banners.order(:created_at).last
    expect(banner).to have_attributes(title: "Novo", link_text: "Ver", display_order: 2, positions: %w[sidebar home_after_hero])
  end
end

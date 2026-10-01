require "rails_helper"

RSpec.describe "Admin::HomeSettings layout do hero", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }

  before do
    ActionController::Base.allow_forgery_protection = false
    host! "localhost"
    sign_in admin
  end

  def html = Nokogiri::HTML(response.body)

  it "oferece os três layouts (Clássico marcado), a posição e a busca por IA com os campos dependentes" do
    get edit_admin_home_setting_path

    expect(response).to have_http_status(:ok)
    expect(html.css("input[name='home_setting[hero_layout]']").map { |node| node["value"] }).to eq(%w[classic bar card])
    expect(html.at_css("input[name='home_setting[hero_layout]'][checked]")["value"]).to eq("classic")
    expect(html.css("input[name='home_setting[hero_search_align]']").map { |node| node["value"] }).to eq(%w[left center right])
    expect(html.at_css("input[name='home_setting[hero_search_align]'][checked]")["value"]).to eq("center")
    expect(html.at_css("input[type='checkbox'][name='home_setting[hero_ai_search_enabled]']")).to be_present
    expect(html.at_css("textarea[name='home_setting[hero_ai_suggestions]']")).to be_present
    expect(html.at_css(".hps-workspace")["data-hero-layout"]).to eq("classic")
    expect(html.css("[data-only-layouts]").map { |node| node["data-only-layouts"] }).to eq(["bar card"]) # a busca por voz/IA vale em todos os layouts
    expect(response.body).to include("ainda não está pronta") # IA da conta sem chave
  end

  it "grava layout, posição, IA e sugestões" do
    patch admin_home_setting_path, params: { home_setting: { hero_layout: "card", hero_search_align: "right", hero_ai_search_enabled: "1", hero_ai_suggestions: "Apto perto do mar\nCasa com quintal" } }

    setting = HomeSetting.find_by!(tenant_id: tenant.id)
    expect(setting).to have_attributes(hero_layout: "card", hero_search_align: "right", hero_ai_search_enabled: true)
    expect(setting.hero_ai_suggestion_list).to eq(["Apto perto do mar", "Casa com quintal"])
  end

  it "recusa layout ou posição desconhecidos e não troca o que estava salvo" do
    patch admin_home_setting_path, params: { home_setting: { hero_layout: "bar" } }
    patch admin_home_setting_path, params: { home_setting: { hero_layout: "carrossel", hero_search_align: "topo" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(HomeSetting.find_by!(tenant_id: tenant.id)).to have_attributes(hero_layout: "bar", hero_search_align: "center")
  end

  it "o aviso some quando a IA da conta está pronta" do
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "token", "Token", tenant:)
    PropertySetting.instance(tenant:).update!(ai_property_search_enabled: true)

    get edit_admin_home_setting_path

    expect(response.body).not_to include("ainda não está pronta")
  end
end

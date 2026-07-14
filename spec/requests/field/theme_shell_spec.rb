require "rails_helper"

RSpec.describe "Field theme shell", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:mobile_headers) { { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile" } }
  let(:broker) { create(:admin_user, :field_agent) }

  before do
    host! "localhost"
    sign_in broker
  end

  it "usa a identidade primária do tenant no modo claro da pessoa" do
    broker.update!(admin_theme_mode: "light")
    LayoutSetting.instance(tenant: broker.tenant).update!(admin_primary_color: "#3E6F9E")
    other_tenant = Tenant.create!(name: "Outro Field", slug: "outro-field-#{SecureRandom.hex(3)}")
    LayoutSetting.instance(tenant: other_tenant).update!(admin_primary_color: "#DC2626")

    get field_root_path, headers: mobile_headers

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.at_css("html")["data-field-theme"]).to eq("light")
    expect(document.css('meta[name="theme-color"]').size).to eq(1)
    expect(document.at_css('meta[name="theme-color"]')["content"]).to eq("#3E6F9E")
    expect(response.body).to include("--field-primary: #3E6F9E")
    expect(response.body).not_to include("#DC2626", "#0d6efd", "#0a58ca")
  end

  it "aplica o modo escuro da pessoa sem consumir o modo legado do tenant" do
    broker.update!(admin_theme_mode: "dark")
    LayoutSetting.instance(tenant: broker.tenant).update!(
      admin_theme_mode: "light",
      admin_primary_color: "#3E6F9E"
    )

    get field_root_path, headers: mobile_headers

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.at_css("html")["data-field-theme"]).to eq("dark")
    expect(document.at_css('meta[name="theme-color"]')["content"]).to eq(LayoutSetting::ADMIN_DARK_THEME[:header])
    expect(response.body).to include("--field-primary: #3E6F9E", "field-theme-toggle", 'aria-checked="true"')
    expect(response.body).to include('data-controller="theme-preference"', 'submit-&gt;theme-preference#submit')
  end
end

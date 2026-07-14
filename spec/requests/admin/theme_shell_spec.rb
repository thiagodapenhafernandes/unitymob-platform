require "rails_helper"

RSpec.describe "Admin theme shell", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:layout_setting) { LayoutSetting.instance(tenant: admin.tenant) }

  before do
    host! "localhost"
    sign_in admin
  end

  def expect_theme_shell(theme:, theme_color:, primary:, drawer: true)
    document = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:ok)
    expect(document.at_css("html")["data-admin-theme"]).to eq(theme)
    expect(document.css('meta[name="theme-color"]').size).to eq(1)
    expect(document.at_css('meta[name="theme-color"]')["content"]).to eq(theme_color)
    expect(response.body).to include("--admin-primary: #{primary}")
    if drawer
      expect(document.at_css('body[data-controller~="ax-drawer"]')).to be_present
      expect(document.at_css('aside.ax-sidebar.ax-drawer-panel[data-ax-drawer-target="panel"]')).to be_present
      expect(document.at_css('.ax-drawer-backdrop[data-ax-drawer-target="backdrop"][hidden]')).to be_present
    else
      expect(document.at_css('[data-controller~="ax-drawer"]')).to be_nil
    end
  end

  it "renderiza dashboard e wizard com o tema light do usuário e a identidade do tenant" do
    admin.update!(admin_theme_mode: "light")
    layout_setting.update!(
      admin_header_color: "#DDE6F0",
      admin_primary_color: "#315F86"
    )
    other_tenant = Tenant.create!(name: "Outro tema", slug: "outro-tema-#{SecureRandom.hex(3)}")
    LayoutSetting.instance(tenant: other_tenant).update!(
      admin_header_color: "#FEE2E2",
      admin_primary_color: "#DC2626"
    )

    get admin_root_path
    expect_theme_shell(theme: "light", theme_color: "#DDE6F0", primary: "#315F86")
    expect(response.body).not_to include("#FEE2E2", "#DC2626")
    expect(response.body).to include('data-controller="theme-preference"', 'submit-&gt;theme-preference#submit')

    get new_admin_captacao_path
    expect_theme_shell(theme: "light", theme_color: "#DDE6F0", primary: "#315F86", drawer: false)
    expect(response.body).not_to include("#FEE2E2", "#DC2626")
  end

  it "renderiza dashboard e wizard com superfícies dark do usuário e identidade primária do tenant" do
    admin.update!(admin_theme_mode: "dark")
    layout_setting.update!(admin_theme_mode: "light", admin_primary_color: "#4B82B8")

    get admin_root_path
    expect_theme_shell(theme: "dark", theme_color: LayoutSetting::ADMIN_DARK_THEME[:header], primary: "#4B82B8")

    get new_admin_captacao_path
    expect_theme_shell(theme: "dark", theme_color: LayoutSetting::ADMIN_DARK_THEME[:header], primary: "#4B82B8", drawer: false)
  end

  it "nao herda o tema da conta publica no Admin do Sistema e preserva o tema da sessao tenant" do
    public_setting = LayoutSetting.instance(tenant: Tenant.public_for)
    public_setting.update!(admin_theme_mode: "dark", admin_primary_color: "#C026D3")
    system_admin = create(:admin_user, super_admin: true)

    sign_out admin
    sign_in system_admin, scope: :admin_user

    expect {
      get admin_system_path
    }.not_to change(LayoutSetting, :count)

    platform_defaults = LayoutSetting.platform_defaults
    expect(platform_defaults).to be_new_record
    expect(platform_defaults.tenant).to be_nil
    expect(Current.tenant).to be_nil
    expect_theme_shell(
      theme: "light",
      theme_color: LayoutSetting::ADMIN_HEADER_DEFAULT,
      primary: LayoutSetting::ADMIN_PRIMARY_DEFAULT
    )
    expect(response.body).to include("Unitymob Plataforma")
    expect(response.body).not_to include("#C026D3")

    tenant = Tenant.create!(name: "Conta impersonada", slug: "conta-impersonada-#{SecureRandom.hex(3)}")
    tenant_setting = LayoutSetting.instance(tenant: tenant)
    tenant_setting.update!(admin_theme_mode: "dark", admin_primary_color: "#3977A8")
    owner = create(:admin_user, :admin, tenant: tenant, profile: tenant.profiles.find_by!(key: "tenant_owner"))
    owner.update!(admin_theme_mode: "dark")

    sign_out system_admin
    sign_in owner, scope: :admin_user
    get admin_root_path

    expect_theme_shell(
      theme: "dark",
      theme_color: LayoutSetting::ADMIN_DARK_THEME[:header],
      primary: "#3977A8"
    )
    expect(response.body).not_to include("#C026D3")
  end
end

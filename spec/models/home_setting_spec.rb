require "rails_helper"

RSpec.describe HomeSetting, type: :model do
  it "aceita declarações CSS para o header público" do
    tenant = Tenant.create!(name: "Conta CSS #{SecureRandom.hex(3)}", slug: "conta-css-#{SecureRandom.hex(3)}")
    setting = described_class.instance(tenant: tenant)

    setting.update!(
      public_header_css: "background-color: rgba(0,9,16,0.4);\nbackdrop-filter: blur(15px);"
    )

    expect(setting.reload.public_header_style).to eq("background-color: rgba(0,9,16,0.4);\nbackdrop-filter: blur(15px);")
  end

  it "bloqueia seletores no CSS do header público" do
    setting = described_class.new(
      tenant: Tenant.default,
      hero_title: "Hero",
      hero_subtitle: "Sub",
      public_header_css: "header { background: red; }"
    )

    expect(setting).not_to be_valid
    expect(setting.errors[:public_header_css]).to include("deve conter apenas declarações CSS, sem seletores ou tags")
  end

  it "controla onde o filtro público de imóveis aparece" do
    setting = described_class.new(
      tenant: Tenant.default,
      hero_title: "Hero",
      hero_subtitle: "Sub",
      search_filter_display_mode: "hero"
    )

    expect(setting).to be_valid
    expect(setting.search_filter_in_hero?).to be(true)
    expect(setting.floating_search_filter?).to be(false)
    expect(setting.mobile_search_filter_in_hero?).to be(true)
    expect(setting.mobile_floating_search_filter?).to be(false)

    setting.search_filter_display_mode = "floating"
    setting.mobile_search_filter_display_mode = "floating"

    expect(setting).to be_valid
    expect(setting.search_filter_in_hero?).to be(false)
    expect(setting.floating_search_filter?).to be(true)
    expect(setting.mobile_search_filter_in_hero?).to be(false)
    expect(setting.mobile_floating_search_filter?).to be(true)
  end

  it "separa visibilidade do filtro entre desktop e mobile" do
    setting = described_class.new(
      tenant: Tenant.default,
      hero_title: "Hero",
      hero_subtitle: "Sub",
      search_filter_display_mode: "hero",
      mobile_search_filter_display_mode: "floating"
    )

    expect(setting).to be_valid
    expect(setting.renders_hero_search_filter?).to be(true)
    expect(setting.renders_floating_search_filter?).to be(true)
    expect(setting.hero_search_filter_visibility_class).to eq("public-hero-search--desktop-only")
    expect(setting.floating_search_filter_visibility_class).to eq("public-global-search--mobile-only")
  end

  it "rejeita modo inválido de exibição do filtro público" do
    setting = described_class.new(
      tenant: Tenant.default,
      hero_title: "Hero",
      hero_subtitle: "Sub",
      search_filter_display_mode: "both",
      mobile_search_filter_display_mode: "hero"
    )

    expect(setting).not_to be_valid
    expect(setting.errors[:search_filter_display_mode]).to be_present
  end
end

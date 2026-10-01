require "rails_helper"

RSpec.describe "public_theme/_luxury_home_hero.html.erb", type: :view do
  it "renderiza hero luxury com busca funcional" do
    tenant = Tenant.create!(name: "Salute Imóveis", slug: "lux-hero")
    view.define_singleton_method(:public_tenant) { tenant }
    assign(:hero_images, [{ source: "https://img.ex/hero.jpg", mobile_source: "https://img.ex/hero-m.jpg" }])
    assign(:property_types, ["Apartamento"])
    assign(:location_options, ["Centro"])
    assign(:home_setting, HomeSetting.instance(tenant: tenant))

    render("public_theme/luxury_home_hero")

    expect(rendered).to include("sl-hero")
    expect(rendered).to include("https://img.ex/hero.jpg")
    expect(rendered).to include("Comprar")
    expect(rendered).to include("Buscar")
  end
end

RSpec.describe "public_theme/_luxury_home_hero.html.erb modes", type: :view do
  def render_luxury_hero(desktop_mode:, mobile_mode:)
    tenant = Tenant.create!(name: "Salute Lux #{SecureRandom.hex(3)}", slug: "lux-modes-#{SecureRandom.hex(3)}")
    view.define_singleton_method(:public_tenant) { tenant }
    setting = HomeSetting.instance(tenant: tenant)
    setting.update!(search_filter_display_mode: desktop_mode, mobile_search_filter_display_mode: mobile_mode)
    assign(:hero_images, [{ source: "https://img.ex/hero.jpg", mobile_source: "https://img.ex/hero-m.jpg" }])
    assign(:property_types, ["Apartamento"])
    assign(:location_options, ["Centro"])
    assign(:home_setting, setting)

    render("public_theme/luxury_home_hero")
  end

  it "omite switch e formulário quando o filtro sai do hero" do
    render_luxury_hero(desktop_mode: "floating", mobile_mode: "floating")

    expect(rendered).to include("sl-hero")
    expect(rendered).not_to include("sl-search")
    expect(rendered).not_to include("sl-transaction")
  end

  it "restringe o formulário por dispositivo como o hero padrão" do
    render_luxury_hero(desktop_mode: "hero", mobile_mode: "floating")

    expect(rendered).to include("public-hero-search--desktop-only", "sl-search")

    render_luxury_hero(desktop_mode: "floating", mobile_mode: "hero")

    expect(rendered).to include("public-hero-search--mobile-only", "sl-search")
  end
end

RSpec.describe "public_theme/_luxury_home_hero.html.erb attachments", type: :view do
  it "renderiza hero luxury com anexos ActiveStorage reais (sem chamar map no anexo)" do
    tenant = Tenant.create!(name: "Salute Lux #{SecureRandom.hex(3)}", slug: "lux-hero-#{SecureRandom.hex(3)}")
    view.define_singleton_method(:public_tenant) { tenant }
    setting = HomeSetting.instance(tenant: tenant)
    slide = setting.hero_slides.build(position: 1, active: true, alt_text: "Hero")
    slide.image.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")),
      filename: "hero.png",
      content_type: "image/png"
    )
    slide.save!
    assign(:hero_images, [{ source: slide.image, mobile_source: slide.image, alt: "Hero" }])
    assign(:property_types, ["Apartamento"])
    assign(:location_options, ["Centro"])
    assign(:home_setting, setting)

    expect { render("public_theme/luxury_home_hero") }.not_to raise_error
    expect(rendered).to include("sl-hero")
  end
end

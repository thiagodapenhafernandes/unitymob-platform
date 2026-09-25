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

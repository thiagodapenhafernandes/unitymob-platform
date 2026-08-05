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
end

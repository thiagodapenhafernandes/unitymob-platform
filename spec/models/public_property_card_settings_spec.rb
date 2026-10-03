require "rails_helper"

RSpec.describe "Configurações do card público" do
  it "mantém a identidade por conta e invalida o HTML ao editar o card" do
    first = Tenant.create!(name: "Card", slug: "card-#{SecureRandom.hex(4)}")
    second = Tenant.create!(name: "Card", slug: "card-#{SecureRandom.hex(4)}")
    a = PropertySetting.instance(tenant: first)
    b = PropertySetting.instance(tenant: second)
    expect(a.card_cta_enabled?).to be(true)
    version = PublicSite::PageVersion.current(first.id)
    a.update!(card_cta_title: "Conheça este imóvel")
    expect(b.reload.card_cta_title).to eq("Gostou deste imóvel?")
    expect(PublicSite::PageVersion.current(first.id)).not_to eq(version)
  end

  it "recusa imagem privada de outra conta e mantém o cadastro" do
    first = Tenant.create!(name: "Card", slug: "card-#{SecureRandom.hex(4)}")
    second = Tenant.create!(name: "Card", slug: "card-#{SecureRandom.hex(4)}")
    setting = PropertySetting.instance(tenant: first)
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")), filename: "card.png", content_type: "image/png", metadata: { tenant_id: second.id })
    setting.card_cta_image = blob
    expect(setting).not_to be_valid
    expect(setting.errors[:card_cta_image]).to include("não pertence a esta conta")
  end

  it "define versões WebP previamente processadas para o upload do card" do
    expect(PropertySetting.reflect_on_attachment(:card_cta_image).named_variants.size).to eq(3)
    setting = PropertySetting.new(card_cta_title: "", card_cta_label: "x" * 41)
    expect(setting).not_to be_valid
    expect(setting.errors[:card_cta_title]).to be_present
    expect(setting.errors[:card_cta_label]).to be_present
  end
end

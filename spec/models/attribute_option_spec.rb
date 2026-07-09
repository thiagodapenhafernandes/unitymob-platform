require "rails_helper"

RSpec.describe AttributeOption, type: :model do
  it "isola unicidade por Tenant" do
    tenant = Tenant.create!(name: "Catalog tenant #{SecureRandom.hex(3)}", slug: "catalog-tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Other catalog tenant #{SecureRandom.hex(3)}", slug: "other-catalog-tenant-#{SecureRandom.hex(3)}")

    tenant.attribute_options.create!(context: "lead", category: "source", name: "Instagram")
    other_option = other_tenant.attribute_options.build(context: "lead", category: "source", name: "Instagram")
    duplicate = tenant.attribute_options.build(context: "lead", category: "source", name: "Instagram")

    expect(other_option).to be_valid
    expect(duplicate).not_to be_valid
  end

  it "sanitiza espacos e pontuacao solta sem remover acentos" do
    option = AttributeOption.new(context: "habitation", category: "imediacoes", name: "  Farmácia.  ")

    option.valid?

    expect(option.name).to eq("Farmácia")
  end

  it "bloqueia duplicidade por chave normalizada no mesmo tenant e categoria" do
    tenant = Tenant.create!(name: "Catalog normalize #{SecureRandom.hex(3)}", slug: "catalog-normalize-#{SecureRandom.hex(3)}")
    tenant.attribute_options.create!(context: "habitation", category: "imediacoes", name: "Farmácia")

    duplicate = tenant.attribute_options.build(context: "habitation", category: "imediacoes", name: "farmacia.")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to include("já existe nesta categoria")
  end

  it "mantem duplicidade isolada por categoria" do
    tenant = Tenant.create!(name: "Catalog category #{SecureRandom.hex(3)}", slug: "catalog-category-#{SecureRandom.hex(3)}")
    tenant.attribute_options.create!(context: "habitation", category: "feature", name: "Piscina")

    option = tenant.attribute_options.build(context: "habitation", category: "infrastructure", name: "piscina.")

    expect(option).to be_valid
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataHygiene::WhitespaceSanitizer do
  it "remove espaços extras sem remover acentos" do
    habitation = create(
      :habitation,
      codigo: "84#{SecureRandom.random_number(10**8)}",
      construtora: "  São   João  ",
      observacoes: "  Linha  um\n\nLinha  dois  "
    )

    described_class.new(execute: true).call

    habitation.reload
    expect(habitation.construtora).to eq("São João")
    expect(habitation.observacoes).to eq("Linha  um\n\nLinha  dois")
  end

  it "junta opções dinâmicas duplicadas por espaços e preserva usos" do
    tenant = Tenant.default
    suffix = SecureRandom.hex(4)
    dirty_name = "Teste  Duplo  #{suffix}"
    clean_name = "Teste Duplo #{suffix}"
    AttributeOption.create!(tenant: tenant, context: "habitation", category: "imediacoes", name: dirty_name)
    AttributeOption.create!(tenant: tenant, context: "habitation", category: "imediacoes", name: clean_name)
    habitation = create(:habitation, codigo: "83#{SecureRandom.random_number(10**8)}", tenant: tenant)
    habitation.address.update!(imediacoes: [dirty_name])

    described_class.new(execute: true).call

    expect(tenant.attribute_options.where(context: "habitation", category: "imediacoes", name: clean_name).count).to eq(1)
    expect(tenant.attribute_options.where(context: "habitation", category: "imediacoes", name: dirty_name)).to be_empty
    expect(habitation.address.reload.imediacoes).to eq([clean_name])
  end
end

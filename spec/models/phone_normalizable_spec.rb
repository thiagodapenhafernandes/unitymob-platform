# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PhoneNormalizable" do
  it "normaliza telefones de proprietários antes de validar" do
    proprietor = build(:proprietor, phone_primary: "(47) 99615-8980", mobile_phone: "00 00000-0000")

    proprietor.valid?

    expect(proprietor.phone_primary).to eq("5547996158980")
    expect(proprietor.mobile_phone).to be_nil
  end

  it "normaliza telefones de leads antes de validar" do
    lead = build(:lead, phone: "21 99087-2427")

    lead.valid?

    expect(lead.phone).to eq("5521990872427")
  end

  it "corrige celular brasileiro antigo com DDD em qualquer model normalizável" do
    store = build(:store, phone: "47 9972-9441")

    store.valid?

    expect(store.phone).to eq("5547999729441")
  end

  it "normaliza telefone secundário de usuário administrativo" do
    admin_user = build(:admin_user, secondary_phone: "47 9972-9441")

    admin_user.valid?

    expect(admin_user.secondary_phone).to eq("5547999729441")
  end

  it "normaliza telefones de contato CRM importado" do
    contact = CrmContact.new(
      vista_code: "CRM-1",
      name: "Contato CRM",
      phone_primary: "47 3311-1067",
      mobile_phone: "47 9972-9441"
    )

    contact.valid?

    expect(contact.phone_primary).to eq("554733111067")
    expect(contact.mobile_phone).to eq("5547999729441")
  end
end

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
end

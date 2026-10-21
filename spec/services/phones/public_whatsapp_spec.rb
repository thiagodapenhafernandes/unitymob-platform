require "rails_helper"

RSpec.describe Phones::PublicWhatsapp do
  cases = JSON.parse(File.read(Rails.root.join("spec/fixtures/phones/public_whatsapp.json")))
  cases.fetch("valid").each do |raw, canonical|
    it "aceita e normaliza #{raw}" do
      phone = described_class.new(raw)
      expect(phone.error).to be_nil
      expect(phone.e164).to eq(canonical)
    end
  end
  cases.fetch("invalid").each do |raw|
    it "rejeita #{raw.inspect} sem completar dígitos" do
      phone = described_class.new(raw)
      expect(phone.error).to be_present
      expect(phone.e164).to be_nil
    end
  end
end

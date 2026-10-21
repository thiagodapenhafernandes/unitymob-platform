require "rails_helper"

RSpec.describe Lead, type: :model do
  it "preserva centavos e aceita valores brasileiros, inclusive zero" do
    lead = described_class.new
    { "1.234,56" => 123456, "12,5" => 1250, "0" => 0, "" => nil }.each do |input, cents|
      lead.closing_commission = input
      expect(lead.closing_commission_cents).to eq(cents)
    end
  end

  it "rejeita negativos, casas extras e formatos ambíguos sem apagar o valor anterior" do
    lead = described_class.new(closing_commission_cents: 12345)
    %w[-1 12,345 12.50 abc].each do |input|
      lead.closing_commission = input
      lead.valid?
      expect(lead.errors[:closing_commission]).to be_present
      expect(lead.closing_commission_cents).to eq(12345)
    end
    lead.closing_commission = "10,00"
    lead.valid?
    expect(lead.errors[:closing_commission]).to be_empty
  end
end

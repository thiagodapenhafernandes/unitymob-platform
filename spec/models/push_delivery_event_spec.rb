require "rails_helper"

RSpec.describe PushDeliveryEvent, type: :model do
  describe ".lead_id_from_tag" do
    it "extrai o lead de tags antigas e tags com contexto adicional" do
      expect(described_class.lead_id_from_tag("lead-123")).to eq(123)
      expect(described_class.lead_id_from_tag("lead-123-45")).to eq(123)
      expect(described_class.lead_id_from_tag("lead-123-property-987-45")).to eq(123)
      expect(described_class.lead_id_from_tag("property-123")).to be_nil
    end
  end
end

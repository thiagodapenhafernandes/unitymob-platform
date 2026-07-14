require "rails_helper"

RSpec.describe Ai::PropertySearch::FilterContract do
  it "remove campos fora da allowlist e normaliza tipos" do
    setting = PropertySetting.instance
    setting.update!(ai_property_search_allowed_fields: %w[transaction_type property_type bedrooms price amenities])

    filters = described_class.new(setting).normalize(
      transaction_type: "sale",
      property_type: "apartments",
      bedrooms_min: "3",
      price_max: "1200000",
      amenities: ["Piscina", ""],
      neighborhood: "Centro",
      sql: "DROP TABLE habitations"
    )

    expect(filters).to eq(
      "transaction_type" => "sale",
      "property_type" => "Apartamento",
      "bedrooms_min" => 3,
      "price_max" => 1_200_000.0,
      "amenities" => ["Piscina"]
    )
  end
end

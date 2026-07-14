require "rails_helper"

RSpec.describe Ai::PropertySearch::Interpreter do
  let(:tenant) { Tenant.create!(name: "IA Interprete #{SecureRandom.hex(3)}", slug: "ia-interprete-#{SecureRandom.hex(4)}") }
  let(:setting) { PropertySetting.instance(tenant: tenant) }

  before do
    setting.update!(
      ai_property_search_allowed_fields: %w[transaction_type property_type city neighborhood development developer_name price amenities],
      ai_property_search_result_fields: %w[property_code title price city development_name]
    )
  end

  it "envia contexto catalogado e filtros atuais para a IA" do
    response_body = {
      "intent" => "search_properties",
      "filters" => {
        "transaction_type" => "sale",
        "property_type" => "apartments",
        "price_min" => 1_500_000,
        "price_max" => 2_000_000
      },
      "missing_required_information" => [],
      "clarifying_question" => nil
    }.to_json

    captured_payload = nil
    client = instance_double(OpenAi::Client)
    allow(OpenAi::Client).to receive(:new).and_return(client)
    allow(client).to receive(:create_response) do |payload|
      captured_payload = payload
      { "output_text" => response_body }
    end

    result = described_class.new(setting:, text: "quero entre um milhão e meio e dois milhões", current_filters: { bedrooms_min: 3 }).call

    expect(result.intent).to eq("search_properties")
    expect(result.filters).to include(
      "transaction_type" => "sale",
      "property_type" => "Apartamento",
      "price_min" => 1_500_000.0,
      "price_max" => 2_000_000.0
    )

    input = JSON.parse(captured_payload.fetch(:input))
    expect(input.fetch("request")).to eq("quero entre um milhão e meio e dois milhões")
    expect(input.fetch("current_filters")).to include("bedrooms_min" => 3)
    expect(input.fetch("catalog")).to include("tenant", "search_config", "catalog")
    expect(captured_payload.fetch(:instructions)).to include("JSON de contexto do catálogo")
    expect(captured_payload.fetch(:text).dig(:format, :name)).to eq("ai_property_search_filters")
  end
end

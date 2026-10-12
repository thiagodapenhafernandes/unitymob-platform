require "rails_helper"

RSpec.describe WebhookSetting do
  it "envia envelope fictício completo em todos os cliques de teste" do
    setting = WebhookSetting.create!(enabled: true, webhook_url: "https://example.test/webhook")
    payloads = []
    allow(WebhookService).to receive(:deliver) do |_url, payload|
      payloads << payload.with_indifferent_access
      { success: true, status: 200 }
    end
    2.times { expect(setting.test_webhook).to be(true) }
    payloads.each do |payload|
      expect(payload).to include(event_name: "test_webhook", diagnostic: true, property_id: "TESTE-SEM-IMOVEL", business_type: "venda", value: 150, currency: "BRL")
      %w[gclid gbraid wbraid fbc fbp client_id client_ip_address client_user_agent utm_source utm_medium utm_campaign placement lead_id].each { |key| expect(payload[key]).to be_present }
      expect(payload[:user_data]).to include("email_address" => "diagnostic@example.test", "phone_number" => "+5547999999999")
      expect(payload[:transaction_id]).to eq(payload[:event_id])
    end
    expect(payloads.map { |p| p[:event_id] }.uniq.size).to eq(2)
  end
end

require "rails_helper"

RSpec.describe WebhookService do
  describe ".send_form_data" do
    it "sends source metadata and tracking parameters in the payload" do
      WebhookSetting.create!(
        enabled: true,
        webhook_url: "https://example.test/webhook"
      )

      request = instance_double(
        ActionDispatch::Request,
        original_url: "https://dev.unitymob.com.br/leads",
        referer: "https://dev.unitymob.com.br/imoveis/apartamento-123?utm_campaign=frente-mar",
        user_agent: "RSpec Browser",
        query_parameters: { "utm_campaign" => "frente-mar" }
      )

      allow(WebhookDeliveryJob).to receive(:perform_later)

      described_class.send_form_data(
        "whatsapp_lead",
        {
          "name" => "Cliente Teste",
          "business_type" => "sale",
          "page_url" => "https://dev.unitymob.com.br/imoveis/apartamento-123",
          "utm_source" => "google"
        },
        request: request
      )

      expect(WebhookDeliveryJob).to have_received(:perform_later) do |_url, raw_payload|
        payload = raw_payload.with_indifferent_access

        expect(payload[:origin_form]).to eq("whatsapp_lead")
        expect(payload[:source].with_indifferent_access).to include(
          "page_url" => "https://dev.unitymob.com.br/imoveis/apartamento-123",
          "request_url" => "https://dev.unitymob.com.br/leads",
          "referrer_url" => "https://dev.unitymob.com.br/imoveis/apartamento-123?utm_campaign=frente-mar",
          "user_agent" => "RSpec Browser"
        )
        expect(payload.dig(:source, :utm).with_indifferent_access).to include(
          "utm_source" => "google",
          "utm_campaign" => "frente-mar"
        )
        expect(payload[:data].with_indifferent_access).to include(
          "name" => "Cliente Teste",
          "business_type" => "sale"
        )
      end
    end
  end
end

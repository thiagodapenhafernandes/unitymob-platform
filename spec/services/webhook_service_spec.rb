require "rails_helper"

RSpec.describe WebhookService do
  describe ".send_form_data" do
    it "sends source metadata and tracking parameters in the payload" do
      WebhookSetting.create!(
        enabled: true,
        webhook_url: "https://example.test/webhook"
      )

      response = instance_double(HTTParty::Response, success?: true)
      request = instance_double(
        ActionDispatch::Request,
        original_url: "https://dev.unitymob.com.br/leads",
        referer: "https://dev.unitymob.com.br/imoveis/apartamento-123?utm_campaign=frente-mar",
        user_agent: "RSpec Browser",
        query_parameters: { "utm_campaign" => "frente-mar" }
      )

      allow(HTTParty).to receive(:post).and_return(response)

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

      expect(HTTParty).to have_received(:post) do |_url, options|
        payload = JSON.parse(options.fetch(:body))

        expect(payload["origin_form"]).to eq("whatsapp_lead")
        expect(payload["source"]).to include(
          "page_url" => "https://dev.unitymob.com.br/imoveis/apartamento-123",
          "request_url" => "https://dev.unitymob.com.br/leads",
          "referrer_url" => "https://dev.unitymob.com.br/imoveis/apartamento-123?utm_campaign=frente-mar",
          "user_agent" => "RSpec Browser"
        )
        expect(payload.dig("source", "utm")).to include(
          "utm_source" => "google",
          "utm_campaign" => "frente-mar"
        )
        expect(payload["data"]).to include(
          "name" => "Cliente Teste",
          "business_type" => "sale"
        )
      end
    end
  end
end

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
        remote_ip: "203.0.113.10",
        cookies: {},
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

    it "adds tracking without changing legacy data or copying personal data to the event" do
      request = instance_double(ActionDispatch::Request,
        original_url: "https://example.test/leads", referer: nil, user_agent: "Browser",
        remote_ip: "203.0.113.10", query_parameters: {},
        cookies: { "unitymob_lgpd_consent" => "accepted", "_fbc" => "fb.1.123.click",
          "_fbp" => "fb.1.123.browser", "_ga" => "GA1.1.123456.1760100000" })
      data = { id: 48213, name: "Maria", email: "maria@example.test", property_id: 9981,
        property_code: "AP1234", business_type: "sale", placement: "property_card",
        attribution_data: { "gclid" => "click", "gbraid" => "braid", "utm_source" => "google" } }
      allow(WebhookDeliveryJob).to receive(:perform_later)
      described_class.send_form_data("whatsapp_lead", data, url: "https://example.test/hook", request: request)
      expect(WebhookDeliveryJob).to have_received(:perform_later) do |_, payload|
        expect(payload).to include(event_name: "lead_created", action_source: "website", lead_id: "48213",
          property_id: 9981, property_code: "AP1234", placement: "property_card",
          "gclid" => "click", "gbraid" => "braid", "utm_source" => "google",
          fbc: "fb.1.123.click", fbp: "fb.1.123.browser", client_id: "123456.1760100000",
          client_ip_address: "203.0.113.10", client_user_agent: "Browser", data: data)
        expect(payload[:event_id]).to match(/\A[0-9a-f-]{36}\z/)
        expect(payload[:event_timestamp]).to eq(Time.iso8601(payload[:timestamp]).to_i)
        expect(payload.keys).not_to include(:name, :email, :phone, :user_data, :value, :currency)
      end
    end

    it "does not read analytics cookies without consent or fabricate missing tracking" do
      request = instance_double(ActionDispatch::Request, original_url: "https://example.test/leads",
        referer: nil, user_agent: "Browser", remote_ip: "203.0.113.10", query_parameters: {},
        cookies: { "unitymob_lgpd_consent" => "rejected", "_fbp" => "private", "_ga" => "GA1.1.123.456" })
      allow(WebhookDeliveryJob).to receive(:perform_later)
      described_class.send_form_data("whatsapp_lead", { id: 1, complemented_inquiry: true },
        url: "https://example.test/hook", request: request)
      expect(WebhookDeliveryJob).to have_received(:perform_later) do |_, payload|
        expect(payload[:event_name]).to eq("lead_inquiry")
        expect(payload.keys.map(&:to_s)).not_to include("client_id", "fbc", "fbp", "gclid")
      end
    end

    it "uses one event identity for all tenant destinations" do
      2.times { |i| WebhookSetting.create!(enabled: true, webhook_url: "https://example.test/hook#{i}") }
      allow(WebhookDeliveryJob).to receive(:perform_later)
      described_class.send_form_data("whatsapp_lead", { id: 1 })
      ids = []
      expect(WebhookDeliveryJob).to have_received(:perform_later).twice do |_, payload|
        ids << payload[:event_id]
        expect(payload[:action_source]).to eq("system_generated")
        expect(payload).not_to have_key(:client_ip_address)
      end
      expect(ids.uniq.size).to eq(1)
    end

    it "keeps admin tests synchronous and clearly identified as tests" do
      setting = WebhookSetting.create!(enabled: true, webhook_url: "https://example.test/hook")
      allow(described_class).to receive(:deliver).and_return(success: true)
      expect(setting.test_webhook).to eq(true)
      expect(described_class).to have_received(:deliver) do |_, payload|
        expect(payload).to include(event_name: "test_webhook", action_source: "system_generated",
          "utm_source" => "unitymob_test", "gclid" => "TEST_GCLID")
        expect(payload).not_to have_key(:lead_id)
      end
    end
  end
end

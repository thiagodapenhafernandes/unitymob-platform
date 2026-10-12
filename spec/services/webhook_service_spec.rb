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
        expect(payload[:legal_bases].as_json).to eq([{ "category" => "data_processing", "type" => "legitimate_interest", "status" => "granted" }])
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

    it "adds tracking and contact data while preserving legacy data" do
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
          property_id: "AP1234", property_code: "AP1234", placement: "property_card",
          "gclid" => "click", "gbraid" => "braid", "utm_source" => "google",
          fbc: "fb.1.123.click", fbp: "fb.1.123.browser", client_id: "123456.1760100000",
          client_ip_address: "203.0.113.10", client_user_agent: "Browser", data: data)
        expect(payload[:event_id]).to match(/\A[0-9a-f-]{36}\z/)
        expect(payload[:transaction_id]).to eq(payload[:event_id])
        expect(payload[:event_timestamp]).to eq(Time.iso8601(payload[:timestamp]).to_i)
        expect(payload[:user_data]).to include(email_address: "maria@example.test", external_id: "48213", address: { first_name: "Maria" })
        expect(payload.keys).not_to include(:name, :email, :phone, :value, :currency)
      end
    end

    it "exports the requested lead contract with saved tracking, contact and monetary value" do
      payload = described_class.build_payload("qualified_lead", {
        id: 48213, name: "Maria Souza", email: "teste@example.test", phone: "(47) 99999-9999",
        property_id: 9981, property_code: "AP1234", business_type: "sale", value: 150.0,
        attribution_data: { "gclid" => "click", "gbraid" => "braid", "wbraid" => "wbraid", "utm_source" => "google" },
        gclid: ""
      })
      expect(payload).to include(event_name: "qualified_lead", lead_id: "48213", business_type: "venda",
        property_id: "AP1234", value: 150.0, currency: "BRL", "gclid" => "click", "gbraid" => "braid", "wbraid" => "wbraid")
      expect(payload[:user_data]).to eq(email_address: "teste@example.test", phone_number: "+5547999999999",
        external_id: "48213", address: { first_name: "Maria", last_name: "Souza" })
    end

    it "resolves property code only inside the supplied lead tenant" do
      property = create(:habitation, tenant: Current.tenant)
      data = { id: 1, tenant_id: property.tenant_id, property_id: property.id }
      expect(described_class.build_payload("qualified_lead", data)[:property_id]).to eq(property.codigo.to_s)
      other = Tenant.create!(name: "Outra", slug: "webhook-property-#{SecureRandom.hex(4)}")
      expect(described_class.build_payload("qualified_lead", data, tenant: other)).not_to have_key(:property_id)
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
        expect(payload[:legal_bases].as_json).to eq([{ "category" => "data_processing", "type" => "legitimate_interest", "status" => "granted" }])
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

require "rails_helper"

RSpec.describe Mobile::AccountRouteRegistrar do
  around do |example|
    old_gateway_url = ENV["GATEWAY_URL"]
    old_token = ENV["GATEWAY_INTERNAL_TOKEN"]
    old_public_url = ENV["PUBLIC_APP_URL"]
    old_whatsapp_gateway_url = ENV["WHATSAPP_WEBHOOK_GATEWAY_URL"]
    old_whatsapp_token = ENV["WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN"]
    ENV["GATEWAY_URL"] = nil
    ENV["GATEWAY_INTERNAL_TOKEN"] = nil
    ENV["WHATSAPP_WEBHOOK_GATEWAY_URL"] = nil
    ENV["WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN"] = nil
    example.run
  ensure
    ENV["GATEWAY_URL"] = old_gateway_url
    ENV["GATEWAY_INTERNAL_TOKEN"] = old_token
    ENV["PUBLIC_APP_URL"] = old_public_url
    ENV["WHATSAPP_WEBHOOK_GATEWAY_URL"] = old_whatsapp_gateway_url
    ENV["WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN"] = old_whatsapp_token
  end

  describe "#configured?" do
    it "is false when any of the required env vars is missing" do
      ENV["GATEWAY_URL"] = nil
      ENV["GATEWAY_INTERNAL_TOKEN"] = "token"
      ENV["PUBLIC_APP_URL"] = "https://app.example.com"

      expect(described_class.new).not_to be_configured
    end

    it "is true once all three are present" do
      ENV["GATEWAY_URL"] = "https://gateway.example.com"
      ENV["GATEWAY_INTERNAL_TOKEN"] = "token"
      ENV["PUBLIC_APP_URL"] = "https://app.example.com"

      expect(described_class.new).to be_configured
    end

    it "falls back to the WhatsApp webhook gateway env vars (same gateway/, same token)" do
      ENV["WHATSAPP_WEBHOOK_GATEWAY_URL"] = "https://webhooks.unitymob.com.br"
      ENV["WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN"] = "shared-token"
      ENV["PUBLIC_APP_URL"] = "https://app.example.com"

      expect(described_class.new).to be_configured
    end

    it "prefers GATEWAY_URL/GATEWAY_INTERNAL_TOKEN over the WhatsApp fallback when both are set" do
      ENV["GATEWAY_URL"] = "https://override.example.com"
      ENV["GATEWAY_INTERNAL_TOKEN"] = "override-token"
      ENV["WHATSAPP_WEBHOOK_GATEWAY_URL"] = "https://webhooks.unitymob.com.br"
      ENV["WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN"] = "shared-token"
      ENV["PUBLIC_APP_URL"] = "https://app.example.com"
      admin_user = create(:admin_user, email: "corretor-#{SecureRandom.hex(4)}@salute.test")

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/internal/account_routes") do |env|
          expect(env.request_headers["Authorization"]).to eq("Bearer override-token")
          [201, {}, "{}"]
        end
      end
      allow_any_instance_of(described_class).to receive(:connection).and_return(Faraday.new { |b| b.adapter(:test, stubs) })

      described_class.new.sync!(admin_user)

      stubs.verify_stubbed_calls
    end
  end

  describe "#sync!" do
    it "does nothing when not configured" do
      ENV["GATEWAY_URL"] = nil
      admin_user = create(:admin_user, email: "corretor-#{SecureRandom.hex(4)}@salute.test")

      expect(Faraday).not_to receive(:new)
      described_class.new.sync!(admin_user)
    end

    it "posts the admin_user email, tenant name and this server's public url" do
      ENV["GATEWAY_URL"] = "https://gateway.example.com"
      ENV["GATEWAY_INTERNAL_TOKEN"] = "internal-token"
      ENV["PUBLIC_APP_URL"] = "https://app.conexaobc.com"
      admin_user = create(:admin_user, email: "corretor-#{SecureRandom.hex(4)}@salute.test")

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/internal/account_routes") do |env|
          expect(env.request_headers["Authorization"]).to eq("Bearer internal-token")
          body = JSON.parse(env.body)
          expect(body).to eq(
            "email" => admin_user.email,
            "tenant_name" => admin_user.tenant.name,
            "target_url" => "https://app.conexaobc.com"
          )
          [201, {}, "{}"]
        end
      end
      allow_any_instance_of(described_class).to receive(:connection).and_return(Faraday.new { |b| b.adapter(:test, stubs) })

      described_class.new.sync!(admin_user)

      stubs.verify_stubbed_calls
    end

    it "logs a warning instead of raising when the gateway call fails" do
      ENV["GATEWAY_URL"] = "https://gateway.example.com"
      ENV["GATEWAY_INTERNAL_TOKEN"] = "internal-token"
      ENV["PUBLIC_APP_URL"] = "https://app.conexaobc.com"
      admin_user = create(:admin_user, email: "corretor-#{SecureRandom.hex(4)}@salute.test")

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/internal/account_routes") { [500, {}, "boom"] }
      end
      allow_any_instance_of(described_class).to receive(:connection).and_return(Faraday.new { |b| b.adapter(:test, stubs) })
      allow(Rails.logger).to receive(:warn)

      expect { described_class.new.sync!(admin_user) }.not_to raise_error
      expect(Rails.logger).to have_received(:warn).with(/falhou email=#{Regexp.escape(admin_user.email)} status=500/)
    end
  end
end

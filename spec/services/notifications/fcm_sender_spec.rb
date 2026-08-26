require "rails_helper"

RSpec.describe Notifications::FcmSender do
  around do |example|
    old_project_id = ENV["FCM_PROJECT_ID"]
    old_service_account = ENV["FCM_SERVICE_ACCOUNT_JSON"]
    example.run
  ensure
    ENV["FCM_PROJECT_ID"] = old_project_id
    ENV["FCM_SERVICE_ACCOUNT_JSON"] = old_service_account
  end

  describe "#configured?" do
    it "is false without FCM_PROJECT_ID/FCM_SERVICE_ACCOUNT_JSON" do
      ENV["FCM_PROJECT_ID"] = nil
      ENV["FCM_SERVICE_ACCOUNT_JSON"] = nil

      expect(described_class.new).not_to be_configured
    end

    it "is true once both env vars are present" do
      ENV["FCM_PROJECT_ID"] = "unitymob-field"
      ENV["FCM_SERVICE_ACCOUNT_JSON"] = '{"type":"service_account"}'

      expect(described_class.new).to be_configured
    end
  end

  describe "#deliver" do
    it "returns a failed result without hitting the network when not configured" do
      ENV["FCM_PROJECT_ID"] = nil
      ENV["FCM_SERVICE_ACCOUNT_JSON"] = nil

      result = described_class.deliver(token: "abc", title: "Novo lead", body: "Teste")

      expect(result.success?).to be(false)
      expect(result.body).to match(/não configurado/)
    end

    it "posts to the FCM v1 endpoint with a bearer token from the service account" do
      ENV["FCM_PROJECT_ID"] = "unitymob-field"
      ENV["FCM_SERVICE_ACCOUNT_JSON"] = '{"type":"service_account"}'

      fake_credentials = instance_double(Google::Auth::ServiceAccountCredentials, fetch_access_token!: { "access_token" => "fake-token" })
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(fake_credentials)

      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.post("/v1/projects/unitymob-field/messages:send") do |env|
          expect(env.request_headers["Authorization"]).to eq("Bearer fake-token")
          body = JSON.parse(env.body)
          expect(body.dig("message", "token")).to eq("device-token")
          expect(body.dig("message", "notification")).to eq("title" => "Novo lead", "body" => "Corretor, atenda rápido")
          [200, { "Content-Type" => "application/json" }, "{}"]
        end
      end
      fake_connection = Faraday.new { |b| b.adapter(:test, stubs) }
      allow_any_instance_of(described_class).to receive(:connection).and_return(fake_connection)

      result = described_class.deliver(token: "device-token", title: "Novo lead", body: "Corretor, atenda rápido", data: { url: "/field" })

      expect(result.success?).to be(true)
      stubs.verify_stubbed_calls
    end
  end
end

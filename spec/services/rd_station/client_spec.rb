require "rails_helper"

RSpec.describe RdStation::Client do
  include ActiveSupport::Testing::TimeHelpers

  let(:tenant) { Tenant.default }
  let(:setting) { RdStationIntegrationSetting.current(tenant:) }
  let(:client) { described_class.new(setting:) }

  before do
    Setting.set(RdStationIntegrationSetting::CLIENT_ID_KEY, "client-id", tenant:)
    Setting.set(RdStationIntegrationSetting::CLIENT_SECRET_KEY, "client-secret", tenant:)
    Setting.set(RdStationIntegrationSetting::API_TOKEN_KEY, "old-access", tenant:)
    Setting.set(RdStationIntegrationSetting::REFRESH_TOKEN_KEY, "refresh-token", tenant:)
  end

  it "renova o access token automaticamente antes de chamada autenticada expirada" do
    travel_to Time.zone.local(2026, 9, 16, 12, 0, 0) do
      Setting.set(RdStationIntegrationSetting::TOKEN_EXPIRES_AT_KEY, 1.minute.ago.iso8601, tenant:)
      token_response = Net::HTTPOK.new("1.1", "200", "OK")
      token_response.instance_variable_set(:@body, {
        access_token: "new-access",
        refresh_token: "new-refresh",
        expires_in: 3600
      }.to_json)
      token_response.instance_variable_set(:@read, true)
      webhook_response = Net::HTTPOK.new("1.1", "200", "OK")
      webhook_response.instance_variable_set(:@read, true)

      expect(client).to receive(:post_json).with(
        RdStation::Client::TOKEN_URL,
        {
          client_id: "client-id",
          client_secret: "client-secret",
          refresh_token: "refresh-token"
        }
      ).and_return(token_response)
      expect(client).to receive(:post_json).twice.with(
        RdStation::Client::WEBHOOKS_URL,
        anything,
        authorization: "Bearer new-access"
      ).and_return(webhook_response)

      client.register_webhooks!(url: "https://example.test/webhooks/rd")

      expect(Setting.tenant_get(RdStationIntegrationSetting::API_TOKEN_KEY, tenant:)).to eq("new-access")
      expect(Setting.tenant_get(RdStationIntegrationSetting::REFRESH_TOKEN_KEY, tenant:)).to eq("new-refresh")
    end
  end
end

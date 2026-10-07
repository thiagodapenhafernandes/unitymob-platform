require "rails_helper"

RSpec.describe TiktokSyncJob do
  let(:admin) { create(:admin_user, :admin) }
  let(:accounts) { [{ "advertiser_id" => "123", "advertiser_name" => "Conta" }] }
  let(:integration) { TiktokIntegration.create!(tenant: admin.tenant, admin_user: admin, access_token: "token", ad_accounts: accounts, selected_account_ids: ["123"]) }
  let(:client) { instance_double(Tiktok::Client) }
  before do
    allow(Tiktok::Client).to receive(:new).and_return(client)
    allow(Tiktok::GatewayClient).to receive(:pause_unselected!)
    allow(Tiktok::GatewayClient).to receive(:owns_callback?) { |url, connection| url == Tiktok::GatewayClient.callback_url(connection) }
    allow(Tiktok::GatewayClient).to receive(:sync!)
    allow(Tiktok::GatewayClient).to receive(:callback_url).with(integration).and_return("https://gateway.example.com/webhooks/tiktok?connection_key=#{integration.route_key}")
    allow(client).to receive(:accounts).and_return(accounts)
    allow(client).to receive(:forms).with("123").and_return([{ "page_id" => "456", "title" => "Apartamento" }])
    allow(client).to receive(:subscriptions) do
      integration.reload.subscriptions.map { |id, subscription| { "subscription_id" => subscription, "callback_url" => Tiktok::GatewayClient.callback_url(integration), "subscription_detail" => { "advertiser_id" => id } } }
    end
  end

  it "registers the route before subscription and retains its identity across syncs" do
    expect(Tiktok::GatewayClient).to receive(:sync!).with(integration, "123", active: true).ordered
    expect(client).to receive(:subscribe).with("123", integration: integration).ordered.once.and_return("sub-1")
    described_class.perform_now(integration.id)
    described_class.perform_now(integration.id)
    expect(integration.reload.subscriptions).to eq({ "123" => "sub-1" })
    expect(integration.catalog.dig("123", "forms")).to eq([{ "id" => "456", "name" => "Apartamento" }])
  end

  it "recovers a remotely created subscription after interruption before local persistence" do
    allow(client).to receive(:subscriptions).and_return([{ "subscription_id" => "sub-1", "callback_url" => Tiktok::GatewayClient.callback_url(integration), "subscription_detail" => { "advertiser_id" => "123" } }])
    expect(client).not_to receive(:subscribe)
    described_class.perform_now(integration.id)
    expect(integration.reload.subscriptions).to eq({ "123" => "sub-1" })
  end

  it "pauses and cancels removed accounts without deleting leads" do
    integration.update!(selected_account_ids: [], subscriptions: { "123" => "sub-1" })
    expect(Tiktok::GatewayClient).to receive(:pause_unselected!).with(integration)
    expect(client).to receive(:unsubscribe).with("sub-1")
    described_class.perform_now(integration.id)
    expect(integration.reload.subscriptions).to eq({})
  end

  it "does not reuse another connection's remote subscription" do
    allow(client).to receive(:subscriptions).and_return([{ "subscription_id" => "foreign", "callback_url" => "https://gateway.example.com/webhooks/tiktok?connection_key=other", "subscription_detail" => { "advertiser_id" => "123" } }])
    expect(client).to receive(:subscribe).with("123", integration: integration).and_return("owned")
    described_class.perform_now(integration.id)
    expect(integration.reload.subscriptions).to eq({ "123" => "owned" })
  end
end

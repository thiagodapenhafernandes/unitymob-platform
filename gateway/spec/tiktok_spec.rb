require "spec_helper"

RSpec.describe "TikTok Gateway" do
  def app; Gateway::App; end
  let(:key) { "9e9c2c58-5696-466f-a251-02bb5f7ee7ea" }
  let(:target) { "https://crm.example.com/webhooks/tiktok/#{key}" }
  let(:entry) { { id: "lead-1", advertiser_id: "123", page_id: "456", changes: [{ field: "email", value: "cliente@example.com" }] } }
  before { ENV["TIKTOK_WEBHOOK_TOKEN"] = "a" * 64 }
  after { ENV.delete("TIKTOK_WEBHOOK_TOKEN") }

  def register(client_key = key)
    post "/internal/tiktok/routes", { client_key: client_key, advertiser_id: "123", target_url: "https://crm.example.com/webhooks/tiktok/#{client_key}", forwarding_secret: "s" * 32, active: true }.to_json,
      { "HTTP_AUTHORIZATION" => "Bearer internal-token", "CONTENT_TYPE" => "application/json" }
  end

  def receive(token = "a" * 64, entries = [entry])
    post "/webhooks/tiktok?webhook_token=#{token}&connection_key=#{key}", { object: 1, entry: entries }.to_json, { "CONTENT_TYPE" => "application/json" }
  end

  it "registers once, isolates each lead and delivers a connection-bound signature once" do
    register
    register
    expect(last_response.status).to eq(200)
    expect(WebhookRoute.where(provider: "tiktok").count).to eq(1)
    signature = Gateway::InternalSignature.sign("#{key}\n#{entry.to_json}", secret: "s" * 32)
    delivery = stub_request(:post, target).with(body: entry.to_json, headers: { "X-Unitymob-Gateway-Signature" => signature }).to_return(status: 200)
    receive
    expect(last_response.status).to eq(200)
    receive
    expect(delivery).to have_been_requested.once
  end

  it "blocks another tenant from claiming the advertiser" do
    register
    register("9e9c2c58-5696-466f-a251-02bb5f7ee7eb")
    expect(last_response.status).to eq(409)
    expect(WebhookRoute.first.client_key).to eq(key)
  end

  it "persists failures and retries using existing delivery infrastructure" do
    register
    stub_request(:post, target).to_return(status: 503)
    receive
    expect(WebhookEvent.last.status).to eq("failed")
    stub_request(:post, target).to_return(status: 200)
    Gateway::RetryFailedEvents.call(now: Time.now + 60)
    expect(WebhookEvent.last.status).to eq("forwarded")
  end

  it "rejects invalid authentication and mixed advertisers without forwarding the batch" do
    register
    receive("bad")
    expect(last_response.status).to eq(401)
    receive("a" * 64, [entry, entry.merge(id: "other", advertiser_id: "999")])
    expect(last_response.status).to eq(409)
    expect(WebhookEvent.count).to eq(0)
  end

  it "pauses removed accounts and rejects delivery to their inactive route" do
    register
    post "/internal/tiktok/connections/#{key}", { advertiser_ids: [] }.to_json, { "HTTP_AUTHORIZATION" => "Bearer internal-token", "CONTENT_TYPE" => "application/json" }
    receive
    expect(last_response.status).to eq(409)
    expect(WebhookRoute.first).not_to be_active
  end
end

RSpec.describe "TikTok OAuth gateway" do
  def app; Gateway::App; end
  let(:state) { "b" * 64 }
  let(:target) { "https://crm.example.com/admin/tiktok_integration/callback" }

  def register
    post "/internal/tiktok/oauth_states", { state: state, return_url: target }.to_json, { "HTTP_AUTHORIZATION" => "Bearer internal-token", "CONTENT_TYPE" => "application/json" }
    expect(last_response.status).to eq(200)
  end

  it "returns the code only to the server-registered destination and consumes state once" do
    register
    get "/oauth/tiktok/callback?#{URI.encode_www_form(state: state, auth_code: 'private-code')}", {}, { "HTTP_REFERER" => "https://business-api.tiktok.com/", "HTTP_SEC_FETCH_SITE" => "cross-site" }
    expect(last_response.status).to eq(302)
    uri = URI(last_response.headers.fetch("location"))
    expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq(target)
    expect(URI.decode_www_form(uri.query).to_h).to eq({ "state" => state, "auth_code" => "private-code" })
    expect(TiktokOauthState.count).to eq(0)
    get "/oauth/tiktok/callback?#{URI.encode_www_form(state: state, auth_code: 'private-code')}", {}, { "HTTP_REFERER" => "https://business-api.tiktok.com/", "HTTP_SEC_FETCH_SITE" => "cross-site" }
    expect(last_response.status).to eq(400)
  end

  it "rejects expired state and ignores an attacker supplied return URL" do
    register
    TiktokOauthState.first.update!(expires_at: Time.now - 1)
    get "/oauth/tiktok/callback?#{URI.encode_www_form(state: state, auth_code: 'code', return_url: 'https://attacker.example.com')}"
    expect(last_response.status).to eq(400)
    expect(last_response.headers['location']).to be_nil
  end

  it "does not register destinations without internal authentication" do
    post "/internal/tiktok/oauth_states", { state: state, return_url: target }.to_json
    expect(last_response.status).to eq(401)
    expect(TiktokOauthState.count).to eq(0)
  end
end

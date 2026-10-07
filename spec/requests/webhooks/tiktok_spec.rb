require "rails_helper"

RSpec.describe "TikTok gateway delivery", type: :request do
  let(:admin) { create(:admin_user, :admin) }
  let(:integration) { TiktokIntegration.create!(tenant: admin.tenant, admin_user: admin, access_token: "token", selected_account_ids: ["123"]) }
  let(:entry) { { id: "lead-1", advertiser_id: "123", page_id: "456", changes: [{ field: "phone_number", value: "11999999999" }] } }
  let(:secret) { "s" * 32 }
  before { host! "localhost"; allow(Tiktok::GatewayClient).to receive(:forwarding_secret).and_return(secret) }

  def deliver(key = integration.route_key, advertiser = "123")
    body = entry.merge(advertiser_id: advertiser).to_json
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{integration.route_key}\n#{body}")}"
    post "/webhooks/tiktok/#{key}", params: body, headers: { "CONTENT_TYPE" => "application/json", "X-Unitymob-Gateway-Provider" => "tiktok", "X-Unitymob-Gateway-Signature" => signature }
  end

  it "queues an authenticated lead for its owning connection" do
    expect { deliver }.to have_enqueued_job(TiktokLeadProcessingJob).with(integration.id, entry.stringify_keys.merge("changes" => [{ "field" => "phone_number", "value" => "11999999999" }]))
    expect(response).to have_http_status(:ok)
  end

  it "rejects an advertiser outside this connection" do
    deliver(integration.route_key, "999")
    expect(response).to have_http_status(:conflict)
  end

  it "cannot replay a signature on another tenant's route" do
    other = create(:admin_user, :admin, tenant: Tenant.create!(name: "Outra", slug: "tiktok-other"))
    target = TiktokIntegration.create!(tenant: other.tenant, admin_user: other, access_token: "token", selected_account_ids: ["123"])
    deliver(target.route_key)
    expect(response).to have_http_status(:unauthorized)
  end
end

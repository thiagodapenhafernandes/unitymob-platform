require "rails_helper"

RSpec.describe "Field::PushSubscriptions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:agent) { create(:admin_user, :field_agent, email: "field-push-#{SecureRandom.hex(8)}@salute.test") }

  before do
    host! "localhost"
    sign_in agent
  end

  it "renova a subscription e desativa o endpoint antigo do mesmo corretor" do
    old_subscription = PushSubscription.create!(
      admin_user: agent,
      endpoint: "https://push.example/old",
      p256dh: "old-p256dh",
      auth: "old-auth",
      active: true
    )

    post field_push_subscriptions_path, params: {
      old_endpoint: old_subscription.endpoint,
      subscription: {
        endpoint: "https://push.example/new",
        expirationTime: nil,
        keys: {
          p256dh: "new-p256dh",
          auth: "new-auth"
        }
      }
    }, as: :json

    expect(response).to have_http_status(:created)
    expect(old_subscription.reload.active).to be(false)

    new_subscription = PushSubscription.find_by!(admin_user: agent, endpoint: "https://push.example/new")
    expect(new_subscription).to have_attributes(
      p256dh: "new-p256dh",
      auth: "new-auth",
      active: true,
      platform: "web"
    )
    expect(new_subscription.last_seen_at).to be_present
  end

  it "mantem apenas a subscription ativa mais recente do mesmo usuario e dispositivo quando nao e Apple" do
    request_user_agent = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 Chrome/149.0.0.0 Mobile Safari/537.36"
    stale_subscription = PushSubscription.create!(
      admin_user: agent,
      endpoint: "https://fcm.googleapis.com/fcm/send/stale",
      p256dh: "stale-p256dh",
      auth: "stale-auth",
      platform: "web",
      user_agent: request_user_agent,
      active: true
    )

    post field_push_subscriptions_path, params: {
      subscription: {
        endpoint: "https://fcm.googleapis.com/fcm/send/current",
        keys: {
          p256dh: "current-p256dh",
          auth: "current-auth"
        }
      }
    }, headers: { "HTTP_USER_AGENT" => request_user_agent }, as: :json

    expect(response).to have_http_status(:created)
    expect(stale_subscription.reload.active).to be(false)
    expect(PushSubscription.active.where(admin_user: agent).pluck(:endpoint)).to contain_exactly("https://fcm.googleapis.com/fcm/send/current")
  end

  it "preserva subscriptions Apple anteriores quando o Safari nao informa old_endpoint" do
    request_user_agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15"
    stale_subscription = PushSubscription.create!(
      admin_user: agent,
      endpoint: "https://web.push.apple.com/stale",
      p256dh: "stale-p256dh",
      auth: "stale-auth",
      platform: "web",
      user_agent: request_user_agent,
      active: true
    )

    post field_push_subscriptions_path, params: {
      subscription: {
        endpoint: "https://web.push.apple.com/current",
        keys: {
          p256dh: "current-p256dh",
          auth: "current-auth"
        }
      }
    }, headers: { "HTTP_USER_AGENT" => request_user_agent }, as: :json

    expect(response).to have_http_status(:created)
    expect(PushSubscription.exists?(stale_subscription.id)).to be(true)
    expect(PushSubscription.where(admin_user: agent).pluck(:endpoint)).to contain_exactly(
      "https://web.push.apple.com/stale",
      "https://web.push.apple.com/current"
    )
  end

  it "registra quando o service worker recebe o push no device" do
    lead = create(:lead, admin_user: agent)
    subscription = PushSubscription.create!(
      admin_user: agent,
      endpoint: "https://web.push.apple.com/current",
      p256dh: "current-p256dh",
      auth: "current-auth",
      platform: "web",
      user_agent: "iPhone",
      active: true,
      last_seen_at: 2.hours.ago
    )

    allow(Rails.logger).to receive(:info)

    post received_field_push_subscriptions_path, params: {
      endpoint: subscription.endpoint,
      reason: "push",
      tag: "lead-#{lead.id}"
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(subscription.reload.last_seen_at).to be > 1.minute.ago
    expect(Rails.logger).to have_received(:info).with(/push recebido no device.*sub=#{subscription.id}.*tag=lead-#{lead.id}/)
    event = PushDeliveryEvent.last
    expect(event).to have_attributes(
      admin_user_id: agent.id,
      push_subscription_id: subscription.id,
      lead_id: lead.id,
      event_type: "device_received",
      tag: "lead-#{lead.id}",
      endpoint_host: "web.push.apple.com"
    )
    expect(event.metadata).to eq("reason" => "push")
  end
end

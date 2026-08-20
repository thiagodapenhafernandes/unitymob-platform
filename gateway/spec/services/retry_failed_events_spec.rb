# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gateway::RetryFailedEvents do
  it "retries due failed events and marks successful deliveries as forwarded" do
    route = WebhookRoute.create!(
      client_key: "conexao",
      phone_number_id: "phone-1",
      target_url: "https://app.conexaobc.com/webhooks/whatsapp",
      forwarding_secret: "forward-secret"
    )
    event = WebhookEvent.create!(
      webhook_route: route,
      provider: "whatsapp",
      event_type: "message",
      payload: { "ok" => true },
      raw_body: { ok: true }.to_json,
      status: "failed",
      attempts: 1,
      received_at: Time.now - 60,
      next_retry_at: Time.now - 1
    )
    stub = stub_request(:post, route.target_url).to_return(status: 200, body: "ok")

    result = described_class.call(now: Time.now)

    expect(result).to have_attributes(retried: 1, forwarded: 1, failed: 0)
    expect(event.reload).to have_attributes(status: "forwarded", attempts: 2, last_error: nil, next_retry_at: nil)
    expect(stub).to have_been_requested
  end

  it "skips events that are not due yet" do
    route = WebhookRoute.create!(
      client_key: "conexao",
      phone_number_id: "phone-1",
      target_url: "https://app.conexaobc.com/webhooks/whatsapp",
      forwarding_secret: "forward-secret"
    )
    WebhookEvent.create!(
      webhook_route: route,
      provider: "whatsapp",
      event_type: "message",
      payload: { "ok" => true },
      status: "failed",
      attempts: 1,
      received_at: Time.now,
      next_retry_at: Time.now + 300
    )

    result = described_class.call(now: Time.now)

    expect(result).to have_attributes(retried: 0, forwarded: 0, failed: 0)
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gateway::EventForwarder do
  it "marks events as failed when the target rejects the payload" do
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
      status: "received",
      received_at: Time.now
    )
    stub_request(:post, route.target_url).to_return(status: 500, body: "boom")

    described_class.call(event:, raw_body: "{}")

    expect(event.reload).to have_attributes(status: "failed", attempts: 1)
    expect(event.last_error).to include("HTTP 500")
  end
end

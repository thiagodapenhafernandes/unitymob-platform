require "rails_helper"

RSpec.describe Automation::WebhookDeliveryService do
  it "refuses blocked destinations without issuing any HTTP request" do
    delivery = AutomationWebhookDelivery.new(url: "http://127.0.0.1:3000/hook", http_method: "post")
    delivery.save!(validate: false)

    expect(HTTParty).not_to receive(:post)
    expect {
      described_class.call(delivery)
    }.to raise_error(ArgumentError, "Blocked webhook destination")

    expect(delivery.reload.status).to eq("failed")
    expect(delivery.error_message).to eq("Blocked webhook destination")
  end

  it "sends allowed deliveries without following redirects" do
    delivery = AutomationWebhookDelivery.create!(
      url: "http://93.184.216.34/hook",
      http_method: "post",
      request_headers: {},
      request_payload: { "event" => "lead_created" }
    )
    response = double(success?: true, code: 200, body: "ok")

    expect(HTTParty).to receive(:post).with(
      "http://93.184.216.34/hook",
      hash_including(timeout: Automation::WebhookDeliveryService::TIMEOUT, follow_redirects: false)
    ).and_return(response)

    described_class.call(delivery)

    expect(delivery.reload.status).to eq("success")
    expect(delivery.response_code).to eq(200)
  end
end

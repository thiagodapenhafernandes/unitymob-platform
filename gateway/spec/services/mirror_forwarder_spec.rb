require "spec_helper"

RSpec.describe Gateway::MirrorForwarder do
  let!(:mirror) do
    WebhookMirror.create!(name: "Dev", provider: "whatsapp", active: true,
      target_url: "https://dev.unitymob.com.br/webhooks/whatsapp", forwarding_secret: "dev-secret")
  end
  let(:event) { WebhookEvent.create!(provider: "whatsapp", event_type: "status", received_at: Time.now) }

  it "limits a failed mirror to one probe per minute" do
    request = stub_request(:post, mirror.target_url).to_return(status: 401)
    now = Time.now
    allow(Time).to receive(:now).and_return(now)

    100.times { described_class.call(event: event, raw_body: "{}") }

    expect(request).to have_been_requested.once
    expect(mirror.reload.last_status).to eq("failed")
    expect(event.reload.status).to eq("received")

    allow(Time).to receive(:now).and_return(now + 60)
    described_class.call(event: event, raw_body: "{}")
    expect(request).to have_been_requested.twice
    expect(mirror.reload.last_status).to eq("failed")

    allow(Time).to receive(:now).and_return(now + 120)
    stub_request(:post, mirror.target_url).to_return(status: 200)
    described_class.call(event: event, raw_body: "{}")
    expect(mirror.reload.last_status).to eq("forwarded")
  end

  it "does not wait for a mirror attempt already in progress, even with a stale model" do
    stale = WebhookMirror.find(mirror.id)
    mirror.update!(last_status: "attempting", last_attempted_at: Time.now)
    request = stub_request(:post, mirror.target_url).to_return(status: 200)

    described_class.new(mirror: stale, event: event, raw_body: "{}").call

    expect(request).not_to have_been_requested
  end

  it "recovers an abandoned attempt and continues mirroring after success" do
    mirror.update!(last_status: "attempting", last_attempted_at: Time.now - 61)
    request = stub_request(:post, mirror.target_url).to_return(status: 200)

    2.times { described_class.call(event: event, raw_body: "{}") }

    expect(request).to have_been_requested.twice
  end

  it "pauses a mirror after a network timeout" do
    request = stub_request(:post, mirror.target_url).to_timeout

    2.times { described_class.call(event: event, raw_body: "{}") }

    expect(request).to have_been_requested.once
    expect(mirror.reload.last_error).to include("Net::")
  end
end

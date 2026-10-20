require_relative "spec_helper"

RSpec.describe "WhatsApp active-route filter" do
  include Rack::Test::Methods

  def app = Gateway::App

  def change(phone, id)
    { "value" => { "metadata" => { "phone_number_id" => phone },
      "statuses" => [{ "id" => id, "status" => "delivered" }] } }
  end

  def deliver(entries)
    body = { "object" => "whatsapp_business_account", "entry" => entries }.to_json
    post "/webhooks/whatsapp", body, "CONTENT_TYPE" => "application/json",
      "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(body, app_secret: "app-secret")
  end

  def route(phone: "known", waba: "known-waba", active: true)
    WebhookRoute.create!(provider: "whatsapp", client_key: phone, phone_number_id: phone,
      waba_id: waba, target_url: "https://#{phone}.test/webhooks/whatsapp",
      forwarding_secret: "secret", active: active)
  end

  it "uses one route query and no writes or external calls for 100 unintegrated events" do
    mirror = WebhookMirror.create!(name: "Dev", provider: "all", active: true,
      target_url: "https://dev.unitymob.com.br", forwarding_secret: "dev-secret")
    dev = stub_request(:post, "https://dev.unitymob.com.br/webhooks/whatsapp").to_return(status: 200)
    expect(Gateway::UnroutedEventAlerter).not_to receive(:call)
    queries = []
    capture = ->(*args) { queries << args.last.fetch(:sql) unless args.last[:name] == "SCHEMA" }

    ActiveSupport::Notifications.subscribed(capture, "sql.active_record") do
      deliver([{ "id" => "unknown-waba", "changes" => 100.times.map { |n| change("unknown", "status-#{n}") } }])
    end

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include("ignored" => 100, "events" => [])
    expect(queries.grep(/SELECT.*webhook_routes/).size).to eq(1)
    expect(queries.grep(/\b(INSERT|UPDATE|DELETE)\b/i)).to be_empty
    expect(WebhookEvent.count).to eq(0)
    expect(mirror.reload.last_attempted_at).to be_nil
    expect(dev).not_to have_been_requested
  end

  it "delivers and mirrors only integrated events from a mixed batch" do
    known = route
    WebhookMirror.create!(name: "Dev", provider: "all", active: true,
      target_url: "https://dev.unitymob.com.br", forwarding_secret: "dev-secret")
    official = stub_request(:post, known.target_url).with { |r| !r.body.include?("foreign") }.to_return(status: 200)
    dev = stub_request(:post, "https://dev.unitymob.com.br/webhooks/whatsapp").with do |r|
      !r.body.include?("foreign") &&
        r.headers["X-Unitymob-Gateway-Signature"] == Gateway::InternalSignature.sign(r.body, secret: "dev-secret")
    end.to_return(status: 200)

    deliver([{ "id" => "foreign-waba", "changes" => [change("foreign", "foreign-status")] },
      { "id" => "known-waba", "changes" => [change("known", "known-status")] }])

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)["ignored"]).to eq(1)
    expect(WebhookEvent.count).to eq(1)
    expect(WebhookEvent.last).to have_attributes(status: "forwarded", external_id: "known-status")
    expect(official).to have_been_requested.once
    expect(dev).to have_been_requested.once
  end

  it "ignores inactive routes and accepts them on the next request after activation" do
    known = route(active: false)
    official = stub_request(:post, known.target_url).to_return(status: 200)
    entries = [{ "id" => "known-waba", "changes" => [change("known", "status-1")] }]

    deliver(entries)
    expect(WebhookEvent.count).to eq(0)
    known.update!(active: true)
    deliver(entries)

    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last.status).to eq("forwarded")
    expect(official).to have_been_requested.once
  end

  it "prefers an exact phone route over another route on the same WABA" do
    route(phone: "first")
    known = route(phone: "second")
    official = stub_request(:post, known.target_url).to_return(status: 200)

    deliver([{ "id" => "known-waba", "changes" => [change("second", "status-1")] }])

    expect(WebhookEvent.last.webhook_route_id).to eq(known.id)
    expect(official).to have_been_requested.once
  end
end

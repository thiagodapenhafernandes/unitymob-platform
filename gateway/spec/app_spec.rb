# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gateway::App do
  def app
    described_class
  end

  it "responds to health checks" do
    get "/up"

    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to include("ok" => true)
  end

  it "answers Meta webhook verification challenges" do
    get "/webhooks/whatsapp", "hub.mode" => "subscribe", "hub.verify_token" => "verify-token", "hub.challenge" => "abc123"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq("abc123")
  end

  it "answers Meta Lead Ads verification challenges" do
    get "/webhooks/meta", "hub.mode" => "subscribe", "hub.verify_token" => "verify-token", "hub.challenge" => "lead123"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to eq("lead123")
  end

  it "rejects webhook payloads with invalid Meta signatures" do
    post "/webhooks/whatsapp", "{}", "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => "sha256=invalid"

    expect(last_response.status).to eq(401)
  end

  it "stores and forwards routed WhatsApp messages" do
    route = WebhookRoute.create!(
      client_key: "conexao",
      tenant_name: "Conexao BC",
      waba_id: "725008303233971",
      phone_number_id: "692164393979141",
      target_url: "https://app.conexaobc.com/webhooks/whatsapp",
      forwarding_secret: "forward-secret"
    )
    payload = {
      object: "whatsapp_business_account",
      entry: [
        {
          id: "725008303233971",
          changes: [
            {
              value: {
                metadata: { phone_number_id: "692164393979141" },
                messages: [{ id: "wamid.message", text: { body: "Ola" } }]
              }
            }
          ]
        }
      ]
    }.to_json
    stub = stub_request(:post, route.target_url).to_return(status: 200, body: "ok")

    post "/webhooks/whatsapp", payload, "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(payload, app_secret: "app-secret")

    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last).to have_attributes(status: "forwarded", webhook_route_id: route.id, raw_body: payload)
    expect(stub).to have_been_requested
  end

  it "stores and forwards routed Meta leadgen events by page id" do
    route = WebhookRoute.create!(
      provider: "meta",
      client_key: "conexao",
      tenant_name: "Conexao BC",
      page_id: "214973675033177",
      target_url: "https://app.conexaobc.com/webhooks/meta",
      forwarding_secret: "forward-secret"
    )
    payload = {
      object: "page",
      entry: [
        {
          id: "214973675033177",
          changes: [
            {
              field: "leadgen",
              value: {
                leadgen_id: "lead-123",
                page_id: "214973675033177",
                form_id: "form-456"
              }
            }
          ]
        }
      ]
    }.to_json
    stub = stub_request(:post, route.target_url).to_return(status: 200, body: "ok")

    post "/webhooks/meta", payload, "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(payload, app_secret: "app-secret")

    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last).to have_attributes(
      provider: "meta",
      status: "forwarded",
      webhook_route_id: route.id,
      external_id: "lead-123",
      event_type: "leadgen",
      page_id: "214973675033177",
      form_id: "form-456",
      raw_body: payload
    )
    expect(stub).to have_been_requested
  end

  it "prefers a Meta leadgen route scoped to page and form" do
    WebhookRoute.create!(
      provider: "meta",
      client_key: "conexao",
      page_id: "214973675033177",
      target_url: "https://app.conexaobc.com/webhooks/meta",
      forwarding_secret: "forward-secret"
    )
    form_route = WebhookRoute.create!(
      provider: "meta",
      client_key: "conexao-form",
      page_id: "214973675033177",
      form_id: "form-456",
      target_url: "https://app.conexaobc.com/webhooks/meta",
      forwarding_secret: "forward-secret"
    )
    payload = {
      entry: [{ changes: [{ field: "leadgen", value: { leadgen_id: "lead-123", page_id: "214973675033177", form_id: "form-456" } }] }]
    }.to_json
    stub_request(:post, form_route.target_url).to_return(status: 200, body: "ok")

    post "/webhooks/meta", payload, "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(payload, app_secret: "app-secret")

    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last.webhook_route_id).to eq(form_route.id)
  end

  it "keeps Meta response successful when the target delivery fails" do
    route = WebhookRoute.create!(
      client_key: "conexao",
      tenant_name: "Conexao BC",
      waba_id: "725008303233971",
      phone_number_id: "692164393979141",
      target_url: "https://app.conexaobc.com/webhooks/whatsapp",
      forwarding_secret: "forward-secret"
    )
    payload = {
      entry: [
        {
          id: "725008303233971",
          changes: [
            {
              value: {
                metadata: { phone_number_id: "692164393979141" },
                messages: [{ id: "wamid.message", text: { body: "Ola" } }]
              }
            }
          ]
        }
      ]
    }.to_json
    stub_request(:post, route.target_url).to_timeout

    post "/webhooks/whatsapp", payload, "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(payload, app_secret: "app-secret")

    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last).to have_attributes(status: "failed", webhook_route_id: route.id)
    expect(WebhookEvent.last.next_retry_at).to be_present
  end

  it "stores unrouted events and still returns 200 to Meta" do
    payload = {
      entry: [{ id: "unknown-waba", changes: [{ value: { metadata: { phone_number_id: "unknown-phone" }, messages: [{ id: "wamid.unknown" }] } }] }]
    }.to_json

    post "/webhooks/whatsapp", payload, "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(payload, app_secret: "app-secret")

    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last).to have_attributes(status: "unrouted", phone_number_id: "unknown-phone")
  end

  it "stores unrouted Meta leadgen events and still returns 200 to Meta" do
    payload = {
      entry: [{ changes: [{ field: "leadgen", value: { leadgen_id: "lead-123", page_id: "unknown-page", form_id: "form-456" } }] }]
    }.to_json

    post "/webhooks/meta", payload, "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(payload, app_secret: "app-secret")

    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last).to have_attributes(status: "unrouted", provider: "meta", page_id: "unknown-page", form_id: "form-456")
  end

  it "sends an optional alert for unrouted Meta leadgen events" do
    alert_url = "https://ops.example.com/gateway-alerts"
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GATEWAY_UNROUTED_ALERT_WEBHOOK_URL").and_return(alert_url)
    payload = {
      entry: [{ changes: [{ field: "leadgen", value: { leadgen_id: "lead-123", page_id: "unknown-page", form_id: "form-456" } }] }]
    }.to_json
    stub = stub_request(:post, alert_url).with do |request|
      body = JSON.parse(request.body)
      body["alert"] == "gateway_unrouted_webhook_event" &&
        body["provider"] == "meta" &&
        body["event_type"] == "leadgen" &&
        body["external_id"] == "lead-123" &&
        body["page_id"] == "unknown-page" &&
        body["form_id"] == "form-456"
    end.to_return(status: 200, body: "ok")

    post "/webhooks/meta", payload, "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(payload, app_secret: "app-secret")

    expect(last_response.status).to eq(200)
    expect(stub).to have_been_requested
  end

  it "routes WhatsApp template status updates by WABA id" do
    route = WebhookRoute.create!(
      client_key: "conexao",
      tenant_name: "Conexao BC",
      waba_id: "1054007410675269",
      phone_number_id: "1266477183219172",
      target_url: "https://app.conexaobc.com/webhooks/whatsapp",
      forwarding_secret: "forward-secret"
    )
    payload = {
      object: "whatsapp_business_account",
      entry: [
        {
          id: "1054007410675269",
          changes: [
            {
              field: "message_template_status_update",
              value: {
                event: "APPROVED",
                reason: "NONE",
                message_template_id: 1_777_522_833_434_571,
                message_template_name: "lead_activation_default",
                message_template_category: "MARKETING",
                message_template_language: "pt_BR"
              }
            }
          ]
        }
      ]
    }.to_json
    stub = stub_request(:post, route.target_url).to_return(status: 200, body: "ok")

    post "/webhooks/whatsapp", payload, "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(payload, app_secret: "app-secret")

    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last).to have_attributes(
      status: "forwarded",
      webhook_route_id: route.id,
      event_type: "message_template_status_update",
      external_id: "1777522833434571",
      waba_id: "1054007410675269",
      phone_number_id: ""
    )
    expect(stub).to have_been_requested
  end

  it "upserts internal routes with bearer token authentication" do
    payload = {
      client_key: "conexao",
      tenant_name: "Conexao BC",
      waba_id: "725008303233971",
      phone_number_id: "692164393979141",
      target_url: "https://app.conexaobc.com/webhooks/whatsapp",
      forwarding_secret: "forward-secret"
    }.to_json

    post "/internal/whatsapp/routes", payload, "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer internal-token"

    expect(last_response.status).to eq(201)
    expect(WebhookRoute.last).to have_attributes(client_key: "conexao", phone_number_id: "692164393979141")
  end

  it "upserts internal Meta routes with bearer token authentication" do
    payload = {
      client_key: "conexao",
      tenant_name: "Conexao BC",
      page_id: "214973675033177",
      target_url: "https://app.conexaobc.com/webhooks/meta",
      forwarding_secret: "forward-secret"
    }.to_json

    post "/internal/meta/routes", payload, "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer internal-token"

    expect(last_response.status).to eq(201)
    expect(WebhookRoute.last).to have_attributes(provider: "meta", client_key: "conexao", page_id: "214973675033177", form_id: nil)
  end

  it "lists webhook events through the protected internal audit endpoint" do
    WebhookEvent.create!(
      provider: "meta",
      event_type: "leadgen",
      external_id: "lead-123",
      page_id: "214973675033177",
      form_id: "form-456",
      status: "unrouted",
      payload: {},
      received_at: Time.now
    )
    WebhookEvent.create!(
      provider: "whatsapp",
      event_type: "message",
      external_id: "wamid-1",
      phone_number_id: "phone-1",
      status: "forwarded",
      payload: {},
      received_at: Time.now
    )

    get "/internal/webhook_events", { "provider" => "meta", "status" => "unrouted" }, "HTTP_AUTHORIZATION" => "Bearer internal-token"

    expect(last_response.status).to eq(200)
    body = JSON.parse(last_response.body)
    expect(body["count"]).to eq(1)
    expect(body["events"].first).to include(
      "provider" => "meta",
      "status" => "unrouted",
      "external_id" => "lead-123",
      "page_id" => "214973675033177",
      "form_id" => "form-456"
    )
  end
end

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
    expect(WebhookEvent.last).to have_attributes(status: "forwarded", webhook_route_id: route.id)
    expect(stub).to have_been_requested
  end

  it "stores unrouted events and still returns 200 to Meta" do
    payload = {
      entry: [{ id: "unknown-waba", changes: [{ value: { metadata: { phone_number_id: "unknown-phone" }, messages: [{ id: "wamid.unknown" }] } }] }]
    }.to_json

    post "/webhooks/whatsapp", payload, "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Gateway::MetaSignature.sign(payload, app_secret: "app-secret")

    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last).to have_attributes(status: "unrouted", phone_number_id: "unknown-phone")
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
end

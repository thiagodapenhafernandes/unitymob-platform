require "rails_helper"

RSpec.describe "Webhooks::PortalLeads", type: :request do
  include ActiveJob::TestHelper

  before { host! "localhost" }

  let(:secret) { "z4p-s3cr3t-k3y" }

  before { Setting.set("grupozap_secret_key", secret, tenant: nil) }

  def auth_header(secret_value = secret)
    "Basic #{Base64.strict_encode64("vivareal:#{secret_value}")}"
  end

  def post_lead(body, headers: {})
    post "/webhooks/portal_leads/grupozap",
         params: body.is_a?(String) ? body : body.to_json,
         headers: { "CONTENT_TYPE" => "application/json", "Authorization" => auth_header }.merge(headers)
  end

  it "enfileira lead válido com Basic correto" do
    expect {
      post_lead({ "originLeadId" => "lead-1", "clientListingId" => "AP-1", "name" => "A" })
    }.to have_enqueued_job(PortalLeadProcessingJob).with(hash_including("originLeadId" => "lead-1"))

    expect(response).to have_http_status(:ok)
  end

  it "rejeita sem Authorization" do
    post "/webhooks/portal_leads/grupozap",
         params: { "originLeadId" => "lead-1" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(PortalLeadProcessingJob).not_to have_been_enqueued
  end

  it "rejeita chave errada" do
    post_lead({ "originLeadId" => "lead-1" }, headers: { "Authorization" => auth_header("errada") })

    expect(response).to have_http_status(:unauthorized)
    expect(PortalLeadProcessingJob).not_to have_been_enqueued
  end

  it "rejeita payload sem originLeadId sem enfileirar" do
    post_lead({ "name" => "Sem id" })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(PortalLeadProcessingJob).not_to have_been_enqueued
  end

  it "rejeita anúncio sem clientListingId sem enfileirar" do
    post_lead({ "originLeadId" => "lead-1", "clientListingId" => " " })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(PortalLeadProcessingJob).not_to have_been_enqueued
  end

  it "aceita simulação MCMV sem código de anúncio para processamento" do
    expect {
      post_lead({ "originLeadId" => "mcmv-1", "leadOrigin" => "MCMV_OLX" })
    }.to have_enqueued_job(PortalLeadProcessingJob)

    expect(response).to have_http_status(:ok)
  end

  it "rejeita JSON que não seja um objeto" do
    post_lead("[]")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(PortalLeadProcessingJob).not_to have_been_enqueued
  end

  it "aceita a assinatura vinculada à integração e rejeita sua reutilização em outra conta" do
    integration = PortalIntegration.for_portal!("zapimoveis", tenant: Tenant.default)
    integration.update!(enabled: true, leads_enabled: true)
    secret = "internal-forwarding-secret"
    allow(Meta::WebhookGatewayClient).to receive(:forwarding_secret).and_return(secret)
    body = { originLeadId: "signed-1", clientListingId: "AP-1" }.to_json
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{integration.lead_route_key}\n#{body}")}"
    headers = { "CONTENT_TYPE" => "application/json", "X-Unitymob-Gateway-Provider" => "grupozap", "X-Unitymob-Gateway-Signature" => signature }
    expect {
      post "/webhooks/portal_leads/grupozap/#{integration.lead_route_key}", params: body, headers: headers
    }.to have_enqueued_job(PortalLeadProcessingJob).with(JSON.parse(body), integration.id)
    expect(response).to have_http_status(:ok)
    other = PortalIntegration.for_portal!("imovelweb", tenant: Tenant.default)
    other.update!(enabled: true, leads_enabled: true)
    post "/webhooks/portal_leads/grupozap/#{other.lead_route_key}", params: body, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end

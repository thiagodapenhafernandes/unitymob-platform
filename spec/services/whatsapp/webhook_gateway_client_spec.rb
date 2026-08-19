require "rails_helper"

RSpec.describe Whatsapp::WebhookGatewayClient do
  let(:tenant) { Tenant.create!(name: "Conexão BC", slug: "conexaoimobiliaria-#{SecureRandom.hex(4)}") }
  let(:integration) do
    tenant.whatsapp_business_integrations.create!(
      status: "connected",
      access_token: "token",
      phone_number_id: "692164393979141",
      waba_id: "725008303233971"
    )
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
  end

  it "nao registra rota quando o gateway nao esta configurado" do
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN").and_return(nil)
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET").and_return(nil)

    result = described_class.new(
      integration: integration,
      tenant: tenant,
      target_url: "https://app.conexaobc.com/webhooks/whatsapp"
    ).register_route

    expect(result).to be_skipped
    expect(result).not_to be_ok
  end

  it "registra a rota do tenant no gateway central" do
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_URL").and_return("https://webhooks.unitymob.com.br")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN").and_return("internal-token")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET").and_return("forward-secret")
    response = instance_double(HTTParty::Response, success?: true, code: 201, body: { route: { id: 1 } }.to_json)
    allow(HTTParty).to receive(:post).and_return(response)

    result = described_class.new(
      integration: integration,
      tenant: tenant,
      target_url: "https://app.conexaobc.com/webhooks/whatsapp"
    ).register_route

    expect(result).to be_ok
    expect(result).not_to be_skipped
    expect(HTTParty).to have_received(:post) do |url, options|
      body = JSON.parse(options[:body]).with_indifferent_access
      expect(url).to eq("https://webhooks.unitymob.com.br/internal/whatsapp/routes")
      expect(options[:headers]).to include(
        "Authorization" => "Bearer internal-token",
        "Content-Type" => "application/json"
      )
      expect(options[:timeout]).to eq(15)
      expect(body).to include(
        client_key: tenant.slug,
        tenant_name: "Conexão BC",
        phone_number_id: "692164393979141",
        waba_id: "725008303233971",
        target_url: "https://app.conexaobc.com/webhooks/whatsapp",
        forwarding_secret: "forward-secret",
        active: true
      )
    end
  end
end

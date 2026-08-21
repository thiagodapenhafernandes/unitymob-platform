require "rails_helper"

RSpec.describe Meta::WebhookGatewayClient do
  let(:tenant) { Tenant.create!(name: "Conexão BC", slug: "conexaoimobiliaria-#{SecureRandom.hex(4)}") }
  let(:admin_user) { create(:admin_user, :admin, tenant: tenant) }
  let(:integration) { create(:user_meta_integration, admin_user: admin_user) }
  let(:page) { create(:meta_facebook_page, user_meta_integration: integration, page_id: "214973675033177", name: "Conexão BC") }
  let(:form) { create(:meta_lead_form, meta_facebook_page: page, form_id: "form-456") }

  before do
    allow(ENV).to receive(:[]).and_call_original
  end

  it "nao registra rota quando o gateway nao esta configurado" do
    allow(ENV).to receive(:[]).with("META_LEADS_WEBHOOK_MODE").and_return("gateway")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN").and_return(nil)
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET").and_return(nil)
    allow(ENV).to receive(:[]).with("META_LEADS_WEBHOOK_TARGET_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("APP_HOST").and_return(nil)

    result = described_class.new(page: page, tenant: tenant).register_route

    expect(result).to be_skipped
    expect(result).not_to be_ok
  end

  it "registra a rota da pagina Meta no gateway central" do
    allow(ENV).to receive(:[]).with("META_LEADS_WEBHOOK_MODE").and_return("gateway")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_URL").and_return("https://webhooks.unitymob.com.br")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN").and_return("internal-token")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET").and_return("forward-secret")
    allow(ENV).to receive(:[]).with("META_LEADS_WEBHOOK_TARGET_URL").and_return("https://app.conexaobc.com/webhooks/meta")
    response = instance_double(HTTParty::Response, success?: true, code: 201, body: { route: { id: 1 } }.to_json)
    allow(HTTParty).to receive(:post).and_return(response)

    result = described_class.new(page: page, tenant: tenant).register_route

    expect(result).to be_ok
    expect(result).not_to be_skipped
    expect(HTTParty).to have_received(:post) do |url, options|
      body = JSON.parse(options[:body]).with_indifferent_access
      expect(url).to eq("https://webhooks.unitymob.com.br/internal/meta/routes")
      expect(options[:headers]).to include(
        "Authorization" => "Bearer internal-token",
        "Content-Type" => "application/json"
      )
      expect(options[:timeout]).to eq(15)
      expect(body).to include(
        client_key: tenant.slug,
        tenant_name: "Conexão BC",
        page_id: "214973675033177",
        form_id: nil,
        target_url: "https://app.conexaobc.com/webhooks/meta",
        forwarding_secret: "forward-secret",
        active: true
      )
    end
  end

  it "registra rota especifica de formulario quando informado" do
    allow(ENV).to receive(:[]).with("META_LEADS_WEBHOOK_MODE").and_return("gateway")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_URL").and_return("https://webhooks.unitymob.com.br")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN").and_return("internal-token")
    allow(ENV).to receive(:[]).with("WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET").and_return("forward-secret")
    allow(ENV).to receive(:[]).with("META_LEADS_WEBHOOK_TARGET_URL").and_return("https://app.conexaobc.com/webhooks/meta")
    response = instance_double(HTTParty::Response, success?: true, code: 201, body: { route: { id: 1 } }.to_json)
    allow(HTTParty).to receive(:post).and_return(response)

    described_class.new(page: page, tenant: tenant, form: form).register_route

    expect(HTTParty).to have_received(:post) do |_url, options|
      body = JSON.parse(options[:body]).with_indifferent_access
      expect(body).to include(page_id: "214973675033177", form_id: "form-456")
    end
  end

  it "nao registra rota quando o modo Meta e app proprio" do
    allow(ENV).to receive(:[]).with("META_LEADS_WEBHOOK_MODE").and_return("direct")

    result = described_class.new(page: page, tenant: tenant).register_route

    expect(result).to be_skipped
    expect(result.error).to include("modo app próprio")
  end
end

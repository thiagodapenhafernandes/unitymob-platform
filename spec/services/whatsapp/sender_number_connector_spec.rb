require "rails_helper"

RSpec.describe Whatsapp::SenderNumberConnector do
  let(:tenant) { Tenant.default }
  let(:sender) do
    create(:whatsapp_sender_number, tenant: tenant, phone_number_id: "phone-1", waba_id: "waba-1").tap do |number|
      allow(number).to receive(:messaging_ready?).and_return(true)
    end
  end
  let(:client) { instance_double(Whatsapp::CloudClient) }
  let(:gateway) { instance_double(Whatsapp::WebhookGatewayClient, register_route: Whatsapp::WebhookGatewayClient::Result.new(ok?: true, skipped?: false)) }

  before do
    allow(Whatsapp::CloudClient).to receive(:new).and_return(client)
    allow(Whatsapp::WebhookGatewayClient).to receive(:new).and_return(gateway)
  end

  def call = described_class.call(sender, tenant: tenant, target_url: "https://dev.test/webhooks/whatsapp")

  it "valida o numero, inscreve o app na WABA e confere a inscricao" do
    allow(client).to receive(:phone_info).and_return(ok: true, data: { "verified_name" => "Salute Imóveis", "quality_rating" => "GREEN" })
    expect(client).to receive(:subscribe_app).and_return(ok: true)
    allow(client).to receive(:subscribed_apps).and_return(ok: true, data: { "data" => [{ "whatsapp_business_api_data" => { "name" => "Salute Imóveis App" } }] })

    result = call

    expect(result).to be_success
    expect(result.subscribed_apps).to eq(["Salute Imóveis App"])
    expect(sender.reload.verified_name).to eq("Salute Imóveis")
  end

  it "avisa quando a Meta recusa a inscricao (token sem acesso a WABA)" do
    allow(client).to receive(:phone_info).and_return(ok: false, error: "sem permissão")
    allow(client).to receive(:subscribe_app).and_return(ok: false, error: "(#100) sem acesso")
    allow(client).to receive(:subscribed_apps).and_return(ok: true, data: { "data" => [] })

    result = call

    expect(result).not_to be_success
    expect(result.warnings.join).to include("Phone Number ID não validado").and include("inscrever o app na WABA waba-1")
  end

  it "pula quando o numero nao tem credenciais de envio" do
    allow(sender).to receive(:messaging_ready?).and_return(false)

    expect(call).to be_skipped
  end
end

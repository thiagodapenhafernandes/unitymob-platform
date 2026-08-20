require "rails_helper"

RSpec.describe Whatsapp::InboundProcessor do
  let!(:integration) do
    WhatsappBusinessIntegration.current(Tenant.default).tap do |record|
      record.update!(status: "connected", phone_number_id: "phone-bsuid", waba_id: "waba-bsuid", access_token: "token")
    end
  end

  def payload(contacts:, messages:)
    { "entry" => [{ "changes" => [{ "field" => "messages",
      "value" => { "metadata" => { "phone_number_id" => integration.phone_number_id }, "contacts" => contacts, "messages" => messages } }] }] }
  end

  it "captura o BSUID (contacts.user_id + messages.from_user_id) na conversa e no lead" do
    described_class.call(payload(
      contacts: [{ "wa_id" => "US.5521999990000", "user_id" => "US.13491208655302741918", "profile" => { "name" => "Fulano" } }],
      messages: [{ "id" => "wamid.1", "from" => "5521999990000", "from_user_id" => "US.13491208655302741918", "type" => "text", "text" => { "body" => "oi" } }]
    ))

    conv = WhatsappConversation.find_by(contact_phone: "5521999990000")
    expect(conv.business_scoped_user_id).to eq("US.13491208655302741918")
    expect(conv.lead.business_scoped_user_id).to eq("US.13491208655302741918")
  end

  it "não descarta mensagem de usuário sem telefone (from omitido, só from_user_id)" do
    expect {
      described_class.call(payload(
        contacts: [{ "user_id" => "US.999", "profile" => { "name" => "Sem Numero" } }],
        messages: [{ "id" => "wamid.2", "from_user_id" => "US.999", "type" => "text", "text" => { "body" => "ola" } }]
      ))
    }.to change(WhatsappConversation, :count).by(1)

    conv = WhatsappConversation.find_by(business_scoped_user_id: "US.999")
    expect(conv.contact_phone).to be_nil
    expect(conv.messages.first.body).to eq("ola")
    expect(conv.lead.business_scoped_user_id).to eq("US.999")
    expect(conv.lead.phone).to be_nil
  end

  it "ignora mensagens de sistema (troca de número)" do
    expect {
      described_class.call(payload(
        contacts: [{ "user_id" => "US.sys" }],
        messages: [{ "id" => "wamid.sys", "from_user_id" => "US.sys", "type" => "system",
                     "system" => { "type" => "user_changed_user_id", "user_id" => "US.sys" } }]
      ))
    }.not_to change(WhatsappMessage, :count)
  end

  it "faz backfill do BSUID numa conversa que já existia só com telefone" do
    conv = WhatsappConversation.create!(tenant: integration.tenant, contact_phone: "5521988887777", status: "open")

    described_class.call(payload(
      contacts: [{ "wa_id" => "5521988887777", "user_id" => "US.B", "profile" => { "name" => "X" } }],
      messages: [{ "id" => "wamid.3", "from" => "5521988887777", "from_user_id" => "US.B", "type" => "text", "text" => { "body" => "hi" } }]
    ))

    expect(conv.reload.business_scoped_user_id).to eq("US.B")
  end

  it "re-vincula conversa/lead quando o BSUID muda (webhook user_id_update)" do
    conv = WhatsappConversation.create!(tenant: integration.tenant, business_scoped_user_id: "US.OLD", status: "open")

    described_class.call({ "entry" => [{ "changes" => [{
      "field" => "user_id_update",
      "value" => { "metadata" => { "phone_number_id" => integration.phone_number_id }, "user_id_update" => [{ "wa_id" => "5521988887777",
        "user_id" => { "previous" => "US.OLD", "current" => "US.NEW" } }] }
    }] }] })

    expect(conv.reload.business_scoped_user_id).to eq("US.NEW")
  end
end

RSpec.describe Whatsapp::CloudClient do
  it "endereça BSUID no campo `recipient` e telefone no campo `to`" do
    client = described_class.new(WhatsappBusinessIntegration.new)
    expect(client.send(:recipient_field, { user_id: "US.13491208655302741918" }))
      .to eq({ recipient: "US.13491208655302741918" })
    expect(client.send(:recipient_field, "21999990000")).to eq({ to: "5521999990000" })
  end

  it "assina o app na WABA da integracao" do
    integration = WhatsappBusinessIntegration.new(
      access_token: "token-123",
      phone_number_id: "phone-123",
      waba_id: "waba-123"
    )
    response = instance_double(HTTParty::Response, body: { success: true }.to_json, code: 200, success?: true)

    allow(HTTParty).to receive(:post).and_return(response)

    result = described_class.new(integration).subscribe_app

    expect(result).to include(ok: true)
    expect(HTTParty).to have_received(:post).with(
      "https://graph.facebook.com/v24.0/waba-123/subscribed_apps",
      query: { access_token: "token-123" },
      timeout: 15
    )
  end

  it "registra o numero usando o PIN de seis digitos" do
    integration = WhatsappBusinessIntegration.new(
      access_token: "token-123",
      phone_number_id: "phone-123"
    )
    response = instance_double(HTTParty::Response, body: { success: true }.to_json, code: 200, success?: true)
    allow(HTTParty).to receive(:post).and_return(response)

    result = described_class.new(integration).register_phone_number(pin: "123-456")

    expect(result).to include(ok: true)
    expect(HTTParty).to have_received(:post).with(
      "https://graph.facebook.com/v24.0/phone-123/register",
      headers: { "Authorization" => "Bearer token-123", "Content-Type" => "application/json" },
      body: { messaging_product: "whatsapp", pin: "123456" }.to_json,
      timeout: 20
    )
  end

  it "rejeita registro quando o PIN nao tem seis digitos" do
    integration = WhatsappBusinessIntegration.new(
      access_token: "token-123",
      phone_number_id: "phone-123"
    )

    result = described_class.new(integration).register_phone_number(pin: "123")

    expect(result).to include(ok: false, error: "Informe um PIN de 6 dígitos para registrar o número.")
  end
end

RSpec.describe Lead do
  it "#whatsapp_recipient usa telefone, e cai no BSUID quando não há telefone" do
    with_phone = build(:lead, phone: "5521999990000")
    expect(with_phone.whatsapp_recipient).to eq("5521999990000")

    only_bsuid = build(:lead, phone: nil, business_scoped_user_id: "US.Q")
    expect(only_bsuid.whatsapp_recipient).to eq({ user_id: "US.Q" })
  end
end

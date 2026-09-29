require "rails_helper"

RSpec.describe Leads::VcardButtonReply do
  let(:tenant) { Tenant.create!(name: "Tenant vcard btn #{SecureRandom.hex(3)}", slug: "tenant-vcard-btn-#{SecureRandom.hex(3)}") }
  let(:broker) do
    profile = tenant.profiles.find_by!(key: "agent")
    create(:admin_user, tenant: tenant, profile: profile, active: true, phone: "21988887777")
  end
  let(:rule) { create(:distribution_rule, tenant: tenant, notify_whatsapp: true) }
  let(:lead) do
    create(:lead, tenant: tenant, name: "Cliente Cartao", phone: "11999999999",
      email: "cliente@teste.com", status: :waiting_acceptance, admin_user: broker, distribution_rule: rule)
  end
  let(:client) { instance_double(Whatsapp::CloudClient) }

  def button_msg(overrides = {})
    {
      "id" => "wamid.reply1", "type" => "interactive", "from" => "5521988887777",
      "interactive" => { "button_reply" => { "id" => "Salvar contato", "title" => "Salvar contato" } },
      "context" => { "id" => "wamid.ctx1" }
    }.merge(overrides)
  end

  before do
    allow_any_instance_of(Lead).to receive(:route_lead)
    LeadSetting.instance(tenant: tenant).update!(vcard_enabled: true)
    lead.activities.create!(kind: "notification_sent",
      metadata: { channel: "whatsapp", message_id: "wamid.ctx1", admin_user_id: broker.id })
    sender = create(:whatsapp_business_integration, tenant: tenant, connected_by_admin_user: broker)
    transport = Notifications::TransportResolver::Result.new(sender: sender, source: :tenant)
    allow(Notifications::TransportResolver).to receive(:whatsapp).with(tenant).and_return(transport)
    allow(Whatsapp::CloudClient).to receive(:new).with(sender).and_return(client)
    allow(client).to receive(:send_contacts).and_return(ok: true, message_id: "wamid.card1")
    allow(client).to receive(:send_text).and_return(ok: true, message_id: "wamid.text1")
  end

  it "envia o cartão e marca atendimento no rodízio" do
    result = Current.set(tenant: tenant) { described_class.call(tenant: tenant, msg: button_msg) }

    expect(result).to be(true)
    expect(client).to have_received(:send_contacts) do |args|
      card = args[:contacts].first
      expect(card[:name][:formatted_name]).to eq("[Unitymob] Cliente Cartao")
      expect(card[:phones]).to eq([{ phone: "+5511999999999", type: "CELL" }])
    end
    expect(lead.reload.status).to eq(Lead.status_value(:em_atendimento))
    expect(lead.activities.where(kind: "accepted")).to exist
    expect(lead.activities.where(kind: "vcard_card_sent")).to exist
  end

  it "ignora com o recurso desligado na conta" do
    LeadSetting.instance(tenant: tenant).update!(vcard_enabled: false)

    result = Current.set(tenant: tenant) { described_class.call(tenant: tenant, msg: button_msg) }

    expect(result).to be(false)
    expect(client).not_to have_received(:send_contacts)
  end

  it "ignora outro botão, sem contexto ou toque de outro corretor" do
    other_title = button_msg("interactive" => { "button_reply" => { "id" => "x", "title" => "Outro" } })
    no_context = button_msg("context" => {})
    other_phone = button_msg("from" => "5521977776666")

    Current.set(tenant: tenant) do
      expect(described_class.call(tenant: tenant, msg: other_title)).to be(false)
      expect(described_class.call(tenant: tenant, msg: no_context)).to be(false)
      expect(described_class.call(tenant: tenant, msg: other_phone)).to be(false)
    end
    expect(client).not_to have_received(:send_contacts)
  end

  it "reivindica e envia o cartão no bolsão" do
    shark_rule = create(:distribution_rule, tenant: tenant, distribution_mode: :shark_tank, notify_whatsapp: true)
    pool_lead = create(:lead, tenant: tenant, name: "Cliente Pool", phone: "11988887777",
      status: :waiting_acceptance, admin_user: nil, distribution_rule: shark_rule)
    pool_lead.activities.create!(kind: "notification_sent",
      metadata: { channel: "whatsapp", message_id: "wamid.ctxpool", admin_user_id: broker.id })
    msg = button_msg("id" => "wamid.replypool", "context" => { "id" => "wamid.ctxpool" })

    result = Current.set(tenant: tenant) { described_class.call(tenant: tenant, msg: msg) }

    expect(result).to be(true)
    expect(pool_lead.reload.admin_user_id).to eq(broker.id)
    expect(client).to have_received(:send_contacts)
  end

  it "avisa sem enviar cartão quando o lead já foi assumido" do
    other_profile = tenant.profiles.find_by!(key: "agent")
    other = create(:admin_user, tenant: tenant, profile: other_profile, active: true, phone: "21900001111")
    lead.update!(admin_user: other, status: Lead.status_value(:em_atendimento))

    result = Current.set(tenant: tenant) { described_class.call(tenant: tenant, msg: button_msg) }

    expect(result).to be(true)
    expect(client).not_to have_received(:send_contacts)
    expect(client).to have_received(:send_text) do |args|
      expect(args[:body]).to include("já foi assumido")
    end
  end

  it "não reenvia o cartão no retry da Meta" do
    Current.set(tenant: tenant) do
      described_class.call(tenant: tenant, msg: button_msg)
      expect(described_class.call(tenant: tenant, msg: button_msg)).to be(true)
    end

    expect(client).to have_received(:send_contacts).once
  end
end

require "rails_helper"

RSpec.describe Leads::NotificationDispatcher do
  let(:corretor) { create(:admin_user, name: "Corretor Push", email: "lead-push-#{SecureRandom.hex(8)}@salute.test", phone: "21988887777") }
  let(:rule) { create(:distribution_rule, notify_push: true, notify_whatsapp: false, notify_email: false, notify_webhook: false) }
  let(:lead) do
    create(
      :lead,
      name: "Cliente Push",
      phone: "11999999999",
      origin: "webhook",
      status: :waiting_acceptance,
      admin_user: corretor,
      distribution_rule: rule
    )
  end

  before do
    Lead.skip_callback(:commit, :after, :route_lead)
    LeadSetting.instance.update!(secure_links_enabled: true, secure_link_push: true)
    allow(Notifications::PushDispatcher).to receive(:deliver).and_return(1)
  end

  after do
    Lead.set_callback(:commit, :after, :route_lead)
  end

  it "abre o card seguro do lead quando o destino do push e detalhes primeiro" do
    PushSetting.instance.update!(lead_click_action: "system")

    described_class.deliver(lead)

    expect(Notifications::PushDispatcher).to have_received(:deliver) do |args|
      expect(args[:admin_user_id]).to eq(corretor.id)
      expect(args[:url]).to include("/s/")
      expect(args[:url]).to include("details=1")
      expect(args[:accept_url]).to be_nil
      expect(args[:urgency]).to eq("high")
      expect(args[:ttl]).to eq(900)
      expect(args[:require_interaction]).to be(true)
      expect(args[:tag]).to eq("lead-#{lead.id}-#{corretor.id}")
    end
  end

  it "abre WhatsApp direto e envia accept_url quando configurado para WhatsApp" do
    PushSetting.instance.update!(lead_click_action: "whatsapp")

    described_class.deliver(lead)

    expect(Notifications::PushDispatcher).to have_received(:deliver) do |args|
      expect(args[:admin_user_id]).to eq(corretor.id)
      expect(args[:url]).to eq(lead.direct_whatsapp_url)
      expect(args[:accept_url]).to include("/s/")
      expect(args[:accept_url]).to include("ack=1")
    end
  end

  it "usa o template configurado e mapeia variaveis dinamicamente no WhatsApp" do
    whatsapp_rule = create(:distribution_rule, notify_push: false, notify_whatsapp: true, notify_email: false, notify_webhook: false)
    whatsapp_lead = create(
      :lead,
      name: "Cliente WhatsApp",
      phone: "21999999999",
      email: "cliente@teste.com",
      origin: "landing",
      status: :waiting_acceptance,
      admin_user: corretor,
      distribution_rule: whatsapp_rule
    )
    template = Tenant.default.whatsapp_templates.create!(
      name: "lead_distribution_custom",
      language: "pt_BR",
      category: "UTILITY",
      body: "Lead {{1}} para {{2}}",
      status: "APPROVED",
      template_type: "text",
      header_format: "none"
    )
    NotificationTemplateSetting.where(tenant_id: Tenant.default.id).delete_all
    Tenant.default.notification_template_settings.create!(
      purpose: "lead_distribution_broker",
      whatsapp_template: template,
      variable_mapping: {
        "1" => "lead_name",
        "2" => "broker_name"
      }
    )
    sender = create(:whatsapp_business_integration, tenant: Tenant.default, connected_by_admin_user: corretor)
    transport = Notifications::TransportResolver::Result.new(sender: sender, source: :tenant)
    client = instance_double(Whatsapp::CloudClient)

    allow(Notifications::TransportResolver).to receive(:whatsapp).with(Tenant.default).and_return(transport)
    allow(Whatsapp::CloudClient).to receive(:new).with(sender).and_return(client)
    allow(client).to receive(:send_template).and_return(ok: true, message_id: "wamid.test")

    described_class.deliver(whatsapp_lead)

    expect(client).to have_received(:send_template) do |args|
      expect(args[:name]).to eq("lead_distribution_custom")
      expect(args[:components].first[:parameters].map { |param| param[:text] }).to eq(["Cliente WhatsApp", corretor.name])
    end
  end
end

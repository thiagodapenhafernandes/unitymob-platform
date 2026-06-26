require "rails_helper"

RSpec.describe Leads::NotificationDispatcher do
  let(:corretor) { create(:admin_user, name: "Corretor Push", email: "lead-push-#{SecureRandom.hex(8)}@salute.test") }
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
end

require "rails_helper"

RSpec.describe Notifications::PushDispatcher do
  let(:admin_user) { create(:admin_user, email: "push-dispatcher-#{SecureRandom.hex(8)}@salute.test") }

  around do |example|
    old_public_key = ENV["VAPID_PUBLIC_KEY"]
    old_private_key = ENV["VAPID_PRIVATE_KEY"]
    ENV["VAPID_PUBLIC_KEY"] = "public-key"
    ENV["VAPID_PRIVATE_KEY"] = "private-key"
    example.run
  ensure
    ENV["VAPID_PUBLIC_KEY"] = old_public_key
    ENV["VAPID_PRIVATE_KEY"] = old_private_key
  end

  before do
    PushSetting.instance.update_columns(
      enabled: true,
      subject_email: "push@example.com",
      vapid_public_key: nil,
      vapid_private_key: nil,
      updated_at: Time.current
    )
  end

  it "retorna zero e registra log quando o usuario nao tem subscription ativa" do
    allow(Rails.logger).to receive(:warn)

    result = described_class.deliver(
      admin_user_id: admin_user.id,
      title: "Novo lead",
      body: "Teste",
      url: "/admin/leads/1/attend"
    )

    expect(result).to eq(0)
    expect(Rails.logger).to have_received(:warn).with(
      "[PushDispatcher] sem subscriptions ativas para admin_user_id=#{admin_user.id}"
    )
    event = PushDeliveryEvent.last
    expect(event).to have_attributes(
      admin_user_id: admin_user.id,
      event_type: "no_active_subscription"
    )
  end

  it "nao envia quando o canal push esta desativado" do
    PushSetting.instance.update!(enabled: false)
    allow(Rails.logger).to receive(:warn)

    result = described_class.deliver(
      admin_user_id: admin_user.id,
      title: "Novo lead",
      body: "Teste",
      url: "/admin/leads/1/attend"
    )

    expect(result).to eq(0)
    expect(Rails.logger).to have_received(:warn).with(
      "[PushDispatcher] push indisponivel para admin_user_id=#{admin_user.id}: configuracao incompleta ou desativada"
    )
    event = PushDeliveryEvent.last
    expect(event).to have_attributes(
      admin_user_id: admin_user.id,
      event_type: "push_unavailable"
    )
  end

  it "envia com prioridade e ttl informados sem marcar last_seen_at como recebimento" do
    lead = create(:lead, admin_user: admin_user)
    subscription = PushSubscription.create!(
      admin_user: admin_user,
      endpoint: "https://web.push.apple.com/current",
      p256dh: "p256dh",
      auth: "auth",
      active: true,
      last_seen_at: 1.day.ago
    )
    response = instance_double(Net::HTTPCreated, code: "201")

    allow(WebPush).to receive(:payload_send).and_return(response)
    allow(Rails.logger).to receive(:info)

    result = described_class.deliver(
      admin_user_id: admin_user.id,
      title: "Novo lead",
      body: "Teste",
      url: "/s/token?details=1",
      tag: "lead-#{lead.id}-#{admin_user.id}",
      urgency: "high",
      ttl: 900,
      require_interaction: true
    )

    expect(result).to eq(1)
    expect(WebPush).to have_received(:payload_send).with(
      hash_including(
        message: include("\"tag\":\"lead-#{lead.id}-#{admin_user.id}\"", "\"require_interaction\":true"),
        endpoint: subscription.endpoint,
        ttl: 900,
        urgency: "high"
      )
    )
    expect(subscription.reload.last_seen_at).to be < 1.hour.ago
    expect(Rails.logger).to have_received(:info).with(/aceito pelo provedor.*urgency=high ttl=900/)
    event = PushDeliveryEvent.last
    expect(event).to have_attributes(
      admin_user_id: admin_user.id,
      push_subscription_id: subscription.id,
      lead_id: lead.id,
      event_type: "provider_accepted",
      tag: "lead-#{lead.id}-#{admin_user.id}",
      endpoint_host: "web.push.apple.com",
      provider_status: "201",
      urgency: "high",
      ttl: 900
    )
    expect(event.endpoint_sha256).to be_present
  end
end

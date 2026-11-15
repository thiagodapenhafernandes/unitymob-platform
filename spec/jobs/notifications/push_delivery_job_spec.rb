require "rails_helper"

RSpec.describe Notifications::PushDeliveryJob, type: :job do
  it "delivers through PushDispatcher with high urgency" do
    allow(Notifications::PushDispatcher).to receive(:deliver)

    described_class.perform_now(
      admin_user_id: 42, title: "Lead atribuído", body: "Toque para atender",
      url: "/admin/leads/7/attend", notification_context: "distribution"
    )

    expect(Notifications::PushDispatcher).to have_received(:deliver).with(
      hash_including(
        admin_user_id: 42, title: "Lead atribuído", body: "Toque para atender",
        url: "/admin/leads/7/attend", urgency: "high", ttl: 3600,
        metadata: { notification_context: "distribution" }
      )
    )
  end
  it "revalida acesso ao lead antes de entregar o push de nova mensagem" do
    user = create(:admin_user, :admin)
    lead = create(:lead, tenant: user.tenant, admin_user: user, skip_automatic_routing: true)
    allow(Notifications::PushDispatcher).to receive(:deliver)
    described_class.perform_now(admin_user_id: user.id, title: 'Nova mensagem', body: 'Confira o lead',
      url: "/admin/leads/#{lead.id}", notification_context: 'instagram_message', lead_id: lead.id)
    expect(Notifications::PushDispatcher).to have_received(:deliver).once
    user.update_columns(active: false)
    described_class.perform_now(admin_user_id: user.id, title: 'Nova mensagem', body: 'Não entregar',
      url: "/admin/leads/#{lead.id}", notification_context: 'instagram_message', lead_id: lead.id)
    expect(Notifications::PushDispatcher).to have_received(:deliver).once
  end

end

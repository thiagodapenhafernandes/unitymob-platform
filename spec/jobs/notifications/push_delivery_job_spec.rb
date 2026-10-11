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
end

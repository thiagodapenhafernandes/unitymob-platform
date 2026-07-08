require "rails_helper"

RSpec.describe Whatsapp::CampaignStuckSweepJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin) }
  let(:sender) { create(:whatsapp_sender_number) }
  let(:template) { WhatsappTemplate.create!(name: "sweep_watchdog", language: "pt_BR", status: "APPROVED", body: "Oi {{1}}") }
  let(:campaign) do
    WhatsappCampaign.create!(
      name: "Campanha varrida",
      whatsapp_template: template,
      whatsapp_sender_number: sender,
      created_by: admin,
      status: "processing",
      started_at: 1.hour.ago,
      send_rate: 10
    )
  end

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = admin.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before { clear_enqueued_jobs }

  it "reencaminha mensagens 'queued' órfãs e revive a corrente morta do BulkSendJob" do
    stuck = campaign.campaign_messages.create!(
      phone_number: "5547999990000", status: "queued", queued_at: 20.minutes.ago
    )
    fresh = campaign.campaign_messages.create!(
      phone_number: "5547999990001", status: "queued", queued_at: 2.minutes.ago
    )
    accepted = campaign.campaign_messages.create!(
      phone_number: "5547999990002", status: "queued", queued_at: 20.minutes.ago,
      external_message_id: "wamid.sweep-1"
    )

    expect {
      described_class.perform_now
    }.to have_enqueued_job(Whatsapp::BulkSendJob).with(campaign.id, tenant_id: campaign.tenant_id)

    expect(stuck.reload.status).to eq("pending")
    expect(fresh.reload.status).to eq("queued")
    expect(accepted.reload.status).to eq("queued")
  end

  it "não re-enfileira BulkSendJob quando a corrente ainda está viva no SolidQueue" do
    campaign.campaign_messages.create!(phone_number: "5547999990000", status: "pending")
    SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "Whatsapp::BulkSendJob",
      arguments: { "arguments" => [campaign.id, { "tenant_id" => campaign.tenant_id }] }
    )

    expect {
      described_class.perform_now
    }.not_to have_enqueued_job(Whatsapp::BulkSendJob)
  end

  it "não mexe em campanha recém-iniciada (processor pode não ter criado as mensagens)" do
    campaign.update!(started_at: 2.minutes.ago)
    stuck = campaign.campaign_messages.create!(
      phone_number: "5547999990000", status: "queued", queued_at: 20.minutes.ago
    )

    expect {
      described_class.perform_now
    }.not_to have_enqueued_job(Whatsapp::BulkSendJob)
    expect(stuck.reload.status).to eq("queued")
    expect(campaign.reload.status).to eq("processing")
  end

  it "reconcilia campanha 'processing' sem pendências para completed" do
    campaign.campaign_messages.create!(
      phone_number: "5547999990000", status: "sent", sent_at: 30.minutes.ago,
      external_message_id: "wamid.sweep-2"
    )

    described_class.perform_now

    expect(campaign.reload.status).to eq("completed")
    expect(campaign.sent_count).to eq(1)
  end

  it "não completa campanha 'processing' sem nenhuma mensagem criada" do
    described_class.perform_now

    expect(campaign.reload.status).to eq("processing")
  end
end

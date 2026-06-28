require "rails_helper"

RSpec.describe WhatsappCampaign, type: :model do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin) }
  let(:template) { WhatsappTemplate.create!(name: "lead_nurture", status: "APPROVED", body: "Oi {{1}}") }
  let(:campaign) { described_class.create!(name: "Campanha", whatsapp_template: template, created_by: admin, status: "processing") }
  let(:lead) { create(:lead, admin_user: admin, phone: "(47) 99999-0000") }

  it "cancela mensagens pendentes e atualiza contadores" do
    campaign.campaign_messages.create!(lead: lead, phone_number: "5547999990000", status: "pending")

    expect(campaign.cancel_pending_messages!).to eq(1)

    message = campaign.campaign_messages.last
    expect(message.status).to eq("cancelled")
    expect(campaign.reload.failed_count).to eq(1)
  end

  it "reenfileira mensagens com falha" do
    campaign.campaign_messages.create!(lead: lead, phone_number: "5547999990000", status: "failed", failure_reason: "HTTP 500")

    expect {
      expect(campaign.retry_failed_messages!).to eq(1)
    }.to have_enqueued_job(Whatsapp::BulkSendJob).with(campaign.id)

    expect(campaign.campaign_messages.last.reload.status).to eq("pending")
  end

  it "calcula custo estimado com parametros do numero de envio" do
    sender = create(:whatsapp_sender_number, cpl_sent_unit_price: 0.75, cpl_fla_unit_price: 0.20)
    campaign.update!(
      whatsapp_sender_number: sender,
      sent_count: 10,
      failed_count: 2,
      replied_count: 4
    )

    expect(campaign.estimated_cost).to eq(7.90.to_d)
    expect(campaign.estimated_cpl).to eq(1.975.to_d)
  end
end

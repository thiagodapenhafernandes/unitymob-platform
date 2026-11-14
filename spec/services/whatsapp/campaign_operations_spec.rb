require "rails_helper"

RSpec.describe WhatsappCampaign, type: :model do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin) }
  let(:template) { WhatsappTemplate.create!(name: "lead_nurture", status: "APPROVED", body: "Oi {{1}}") }
  let(:campaign) { described_class.create!(name: "Campanha", whatsapp_template: template, created_by: admin, status: "processing") }
  let(:lead) { create(:lead, admin_user: admin, phone: "(47) 99999-0000") }

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = admin.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

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
    }.to have_enqueued_job(Whatsapp::BulkSendJob).with(campaign.id, tenant_id: campaign.tenant_id)

    expect(campaign.campaign_messages.last.reload.status).to eq("pending")
  end

end

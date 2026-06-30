require "rails_helper"

RSpec.describe "WhatsApp campaign dispatch jobs", type: :job do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin) }
  let(:sender) { create(:whatsapp_sender_number) }
  let(:template) { WhatsappTemplate.create!(name: "lead_nurture", language: "pt_BR", status: "APPROVED", body: "Oi {{1}}") }
  let(:campaign) do
    WhatsappCampaign.create!(
      name: "Campanha assincrona",
      whatsapp_template: template,
      whatsapp_sender_number: sender,
      created_by: admin,
      status: "processing",
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

  it "enfileira apenas mensagens pendentes no lote" do
    pending_message = campaign.campaign_messages.create!(phone_number: "5547999990000", status: "pending")
    queued_message = campaign.campaign_messages.create!(phone_number: "5547999990001", status: "queued")

    expect {
      Whatsapp::BulkSendJob.perform_now(campaign.id, tenant_id: campaign.tenant_id)
    }.to have_enqueued_job(Whatsapp::CampaignMessageDispatchJob).with(pending_message.id, tenant_id: campaign.tenant_id)
    expect(enqueued_jobs.count { |job| job[:job] == Whatsapp::CampaignMessageDispatchJob }).to eq(1)
    expect(enqueued_jobs.flatten).not_to include(queued_message.id)
  end

  it "nao processa lote quando o tenant_id nao corresponde a campanha" do
    other_tenant = Tenant.create!(name: "Outro lote #{SecureRandom.hex(3)}", slug: "outro-lote-#{SecureRandom.hex(3)}")
    campaign.campaign_messages.create!(phone_number: "5547999990000", status: "pending")

    expect {
      Whatsapp::BulkSendJob.perform_now(campaign.id, tenant_id: other_tenant.id)
    }.not_to have_enqueued_job(Whatsapp::CampaignMessageDispatchJob)
  end

  it "reserva a mensagem com lock antes de chamar o sender" do
    message = campaign.campaign_messages.create!(phone_number: "5547999990000", status: "pending")
    allow(Whatsapp::CampaignMessageSender).to receive(:call)

    Whatsapp::CampaignMessageDispatchJob.perform_now(message.id, tenant_id: campaign.tenant_id)
    Whatsapp::CampaignMessageDispatchJob.perform_now(message.id, tenant_id: campaign.tenant_id)

    expect(Whatsapp::CampaignMessageSender).to have_received(:call).once
    expect(message.reload.status).to eq("queued")
  end

  it "nao reserva mensagem quando o tenant_id nao corresponde a mensagem" do
    other_tenant = Tenant.create!(name: "Outro dispatch #{SecureRandom.hex(3)}", slug: "outro-dispatch-#{SecureRandom.hex(3)}")
    message = campaign.campaign_messages.create!(phone_number: "5547999990000", status: "pending")
    allow(Whatsapp::CampaignMessageSender).to receive(:call)

    Whatsapp::CampaignMessageDispatchJob.perform_now(message.id, tenant_id: other_tenant.id)

    expect(Whatsapp::CampaignMessageSender).not_to have_received(:call)
    expect(message.reload.status).to eq("pending")
  end
end

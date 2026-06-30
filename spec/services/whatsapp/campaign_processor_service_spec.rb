require "rails_helper"

RSpec.describe Whatsapp::CampaignProcessorService do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin) }

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = admin.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  let(:template) do
    WhatsappTemplate.create!(
      name: "lead_nurture",
      language: "pt_BR",
      status: "APPROVED",
      body: "Oi {{1}}, origem {{2}}."
    )
  end
  let(:campaign) do
    WhatsappCampaign.create!(
      name: "Nutrição de leads",
      whatsapp_template: template,
      created_by: admin,
      status: "processing",
      send_rate: 20,
      audience_filters: { status: Lead.status_value(:novo), origin: "site" },
      template_variables: { "1" => "{{nome}}", "2" => "{{origem}}" }
    )
  end

  before do
    clear_enqueued_jobs
    create(:whatsapp_business_integration, connected_by_admin_user: admin)
  end

  it "materializa mensagens para a audiência filtrada e enfileira o disparo em lote" do
    matched = create(:lead, name: "Lead Certo", phone: "(47) 99999-0000", origin: "site", status: :novo)
    create(:lead, phone: "(47) 98888-0000", origin: "portal", status: :novo)
    lead_without_phone = create(:lead, phone: "(47) 97777-0000", origin: "site", status: :novo)
    lead_without_phone.update_column(:phone, nil)

    expect {
      described_class.call(campaign)
    }.to change(WhatsappCampaignMessage, :count).by(1)
      .and have_enqueued_job(Whatsapp::BulkSendJob).with(campaign.id, tenant_id: campaign.tenant_id)

    message = campaign.campaign_messages.last
    expect(message.tenant).to eq(campaign.tenant)
    expect(message.lead).to eq(matched)
    expect(message.phone_number).to eq("5547999990000")
    expect(message.template_variables).to eq("1" => "Lead Certo", "2" => "site")
    expect(campaign.reload.requested_recipients).to eq(1)
    expect(campaign.total_recipients).to eq(1)
  end
end

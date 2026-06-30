require "rails_helper"

RSpec.describe "Automation webhook action" do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, admin_user: admin, name: "Maria Lead", phone: "(47) 99999-0000", email: "maria@example.test", origin: "site") }
  let(:template) { WhatsappTemplate.create!(name: "lead_nurture", status: "APPROVED", body: "Oi {{1}}") }
  let(:campaign) { WhatsappCampaign.create!(name: "Campanha WhatsApp", whatsapp_template: template, created_by: admin) }
  let(:campaign_message) { campaign.campaign_messages.create!(lead: lead, phone_number: "5547999990000", status: "replied") }
  let(:conversation) { WhatsappConversation.create!(lead: lead, contact_phone: "5547999990000", business_scoped_user_id: "bsuid-123") }
  let(:inbound_message) { conversation.messages.create!(direction: "inbound", wa_message_id: "wamid.reply", msg_type: "text", body: "Tenho interesse nesse imóvel", status: "delivered") }
  let(:event) do
    AutomationEvent.create!(
      lead: lead,
      name: "whatsapp_campaign_message_replied",
      source: "whatsapp_campaign",
      payload: {
        "distribution_rule_id" => 12,
        "admin_user_id" => admin.id,
        "whatsapp_campaign_id" => campaign.id,
        "whatsapp_campaign_message_id" => campaign_message.id,
        "inbound_whatsapp_message_id" => inbound_message.id
      }
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

  it "cria entrega de webhook com tokens do lead/evento e enfileira envio" do
    action = {
      "type" => "send_webhook",
      "url" => "https://example.test/hooks/leads",
      "http_method" => "POST",
      "headers" => "X-Lead: {{nome}}\nX-Rule: {{event.distribution_rule_id}}",
      "payload_template" => {
        lead_id: "{{event.admin_user_id}}",
        name: "{{nome}}",
        phone: "{{telefone}}",
        rule_id: "{{event.distribution_rule_id}}",
        campaign_id: "{{campaign.id}}",
        campaign: "{{campaign.name}}",
        message_id: "{{campaign_message.id}}",
        message_status: "{{campaign_message.status}}",
        reply_body: "{{whatsapp.message_body}}",
        reply_bsuid: "{{whatsapp.bsuid}}"
      }.to_json
    }

    expect {
      described_executor.execute(action)
    }.to change(AutomationWebhookDelivery, :count).by(1)
      .and have_enqueued_job(Automation::WebhookDeliveryJob)

    delivery = AutomationWebhookDelivery.last
    expect(delivery.lead).to eq(lead)
    expect(delivery.automation_event).to eq(event)
    expect(delivery.http_method).to eq("post")
    expect(delivery.request_headers).to include("X-Lead" => "Maria Lead", "X-Rule" => "12")
    expect(delivery.request_payload).to include(
      "lead_id" => admin.id.to_s,
      "name" => "Maria Lead",
      "phone" => "(47) 99999-0000",
      "rule_id" => "12",
      "campaign_id" => campaign.id.to_s,
      "campaign" => "Campanha WhatsApp",
      "message_id" => campaign_message.id.to_s,
      "message_status" => "replied",
      "reply_body" => "Tenho interesse nesse imóvel",
      "reply_bsuid" => "bsuid-123"
    )
    expect(lead.activities.where(kind: "automation_webhook")).to exist
  end

  it "cria webhook com tokens do destinatario sem criar lead" do
    recipient = campaign.campaign_recipients.create!(
      name: "Cliente Planilha",
      phone_number: "5547991112222",
      email: "cliente@example.test",
      origin: "planilha",
      tags: ["Premium"],
      conversion_status: "pending"
    )
    recipient_message = campaign.campaign_messages.create!(
      whatsapp_campaign_recipient: recipient,
      phone_number: recipient.phone_number,
      status: "replied"
    )
    recipient_event = AutomationEvent.create!(
      lead: nil,
      name: "whatsapp_campaign_message_replied",
      source: "whatsapp_campaign",
      payload: {
        "whatsapp_campaign_id" => campaign.id,
        "whatsapp_campaign_message_id" => recipient_message.id,
        "whatsapp_campaign_recipient_id" => recipient.id
      }
    )
    action = {
      "type" => "send_webhook",
      "url" => "https://example.test/hooks/recipients",
      "http_method" => "POST",
      "headers" => "X-Recipient: {{recipient.name}}",
      "payload_template" => {
        recipient_name: "{{recipient.name}}",
        recipient_phone: "{{recipient.phone}}",
        conversion_status: "{{recipient.conversion_status}}"
      }.to_json
    }
    lead_count = Lead.count
    activity_count = LeadActivity.count

    expect {
      Automation::ActionExecutor.new(nil, automation_event: recipient_event).execute(action)
    }.to change(AutomationWebhookDelivery, :count).by(1)
      .and have_enqueued_job(Automation::WebhookDeliveryJob)

    delivery = AutomationWebhookDelivery.last
    expect(Lead.count).to eq(lead_count)
    expect(LeadActivity.count).to eq(activity_count)
    expect(delivery.lead).to be_nil
    expect(delivery.automation_event).to eq(recipient_event)
    expect(delivery.request_headers).to include("X-Recipient" => "Cliente Planilha")
    expect(delivery.request_payload).to include(
      "recipient_name" => "Cliente Planilha",
      "recipient_phone" => "5547991112222",
      "conversion_status" => "pending"
    )
  end

  def described_executor
    Automation::ActionExecutor.new(lead, automation_event: event)
  end
end

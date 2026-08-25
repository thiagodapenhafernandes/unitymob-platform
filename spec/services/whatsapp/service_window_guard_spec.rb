require "rails_helper"

RSpec.describe Whatsapp::ServiceWindowGuard do
  it "trava a conversa apos apresentacao aceita sem resposta do lead" do
    tenant = Tenant.create!(name: "Guard", slug: "guard-#{SecureRandom.hex(3)}")
    lead = create(:lead, tenant: tenant, name: "Antonio Olivo")
    conversation = WhatsappConversation.create!(tenant:, lead:, contact_phone: "5547999990100")
    conversation.messages.create!(
      tenant:,
      direction: "outbound",
      status: "read",
      msg_type: "template",
      template_name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
      wa_message_id: "wamid.presentation",
      body: "Oi"
    )

    result = described_class.call(conversation:)

    expect(result).to be_locked
    expect(result.message).to include("Antonio Olivo")
    expect(result.template_name).to eq(Whatsapp::LeadActivationTemplate::TEMPLATE_NAME)
  end

  it "libera quando o lead responde depois da apresentacao" do
    tenant = Tenant.create!(name: "Guard Livre", slug: "guard-livre-#{SecureRandom.hex(3)}")
    lead = create(:lead, tenant: tenant)
    conversation = WhatsappConversation.create!(tenant:, lead:, contact_phone: "5547999990101")
    sent_at = 10.minutes.ago
    conversation.messages.create!(
      tenant:,
      direction: "outbound",
      status: "delivered",
      msg_type: "template",
      template_name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
      wa_message_id: "wamid.presentation",
      body: "Oi",
      created_at: sent_at,
      updated_at: sent_at
    )
    conversation.messages.create!(
      tenant:,
      direction: "inbound",
      status: "delivered",
      msg_type: "text",
      body: "Pode mandar",
      created_at: 1.minute.ago,
      updated_at: 1.minute.ago
    )

    expect(described_class.call(conversation:)).not_to be_locked
  end
end

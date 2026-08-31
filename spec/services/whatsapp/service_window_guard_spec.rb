require "rails_helper"

RSpec.describe Whatsapp::ServiceWindowGuard do
  it "trava a conversa apos apresentacao aceita sem resposta do lead" do
    tenant = Tenant.create!(name: "Guard", slug: "guard-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, tenant: tenant)
    create(:whatsapp_business_integration, tenant: tenant, connected_by_admin_user: admin)
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
    admin = create(:admin_user, tenant: tenant)
    create(:whatsapp_business_integration, tenant: tenant, connected_by_admin_user: admin)
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

  it "trava conversa sem inbound recente quando a integracao esta pronta" do
    tenant = Tenant.create!(name: "Guard Janela", slug: "guard-janela-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, tenant: tenant)
    create(:whatsapp_business_integration, tenant: tenant, connected_by_admin_user: admin)
    lead = create(:lead, tenant: tenant, name: "Lead Novo")
    conversation = WhatsappConversation.create!(tenant:, lead:, contact_phone: "5547999990102")

    result = described_class.call(conversation:)

    expect(result).to be_locked
    expect(result.message).to include("janela de 24h")
  end

  it "trava envio quando a integracao nao esta configurada" do
    tenant = Tenant.create!(name: "Guard Sem Integracao", slug: "guard-sem-integracao-#{SecureRandom.hex(3)}")
    lead = create(:lead, tenant: tenant)
    conversation = WhatsappConversation.create!(tenant:, lead:, contact_phone: "5547999990105")

    result = described_class.call(conversation:)

    expect(result).to be_locked
    expect(result.message).to include("Integração WhatsApp não configurada")
    expect(result.template_name).to be_nil
  end

  it "libera conversa com inbound nas ultimas 24h" do
    tenant = Tenant.create!(name: "Guard Inbound", slug: "guard-inbound-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, tenant: tenant)
    create(:whatsapp_business_integration, tenant: tenant, connected_by_admin_user: admin)
    lead = create(:lead, tenant: tenant)
    conversation = WhatsappConversation.create!(tenant:, lead:, contact_phone: "5547999990103")
    conversation.messages.create!(
      tenant:,
      direction: "inbound",
      status: "delivered",
      msg_type: "text",
      body: "Oi",
      created_at: 2.hours.ago,
      updated_at: 2.hours.ago
    )

    expect(described_class.call(conversation:)).not_to be_locked
  end

  it "libera conversa com janela estendida de ponto de entrada ainda aberta" do
    tenant = Tenant.create!(name: "Guard Entrada", slug: "guard-entrada-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, tenant: tenant)
    create(:whatsapp_business_integration, tenant: tenant, connected_by_admin_user: admin)
    lead = create(:lead, tenant: tenant)
    conversation = WhatsappConversation.create!(
      tenant:,
      lead:,
      contact_phone: "5547999990104",
      free_entry_point_expires_at: 1.hour.from_now
    )
    conversation.messages.create!(
      tenant:,
      direction: "inbound",
      status: "delivered",
      msg_type: "text",
      body: "Oi",
      created_at: 30.hours.ago,
      updated_at: 30.hours.ago
    )

    expect(described_class.call(conversation:)).not_to be_locked
  end
end

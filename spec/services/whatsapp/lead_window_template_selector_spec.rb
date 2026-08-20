require "rails_helper"

RSpec.describe Whatsapp::LeadWindowTemplateSelector do
  def approve_template(tenant:, integration:, name:, category: "MARKETING")
    definition = Whatsapp::LeadConversationTemplates.find(name)
    WhatsappTemplate.create!(
      tenant: tenant,
      waba_id: integration.waba_id,
      name: name,
      language: "pt_BR",
      status: "APPROVED",
      category: definition&.category || category,
      template_type: "text",
      header_format: "none",
      body: definition&.body || "Oi {{1}}"
    )
  end

  it "prioriza template de agenda quando ha compromisso futuro aprovado" do
    tenant = Tenant.create!(name: "Agenda", slug: "selector-agenda-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, tenant: tenant)
    integration = WhatsappBusinessIntegration.current(tenant)
    integration.update!(waba_id: "waba-selector-agenda")
    lead = create(:lead, tenant: tenant)
    conversation = WhatsappConversation.create!(tenant: tenant, lead: lead, contact_phone: "5547999990201")
    approve_template(tenant: tenant, integration: integration, name: "lead_appointment_reminder")
    Appointment.create!(
      tenant: tenant,
      lead: lead,
      admin_user: admin,
      title: "Visita",
      starts_at: 1.day.from_now,
      status: "agendado"
    )

    result = described_class.call(conversation: conversation, admin_user: admin)

    expect(result.template.name).to eq("lead_appointment_reminder")
    expect(result.label).to eq("Usar lembrete de agenda")
  end

  it "usa retomada quando ja existe historico e nao ha agenda ou tarefa aprovada" do
    tenant = Tenant.create!(name: "Retomada", slug: "selector-followup-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, tenant: tenant)
    integration = WhatsappBusinessIntegration.current(tenant)
    integration.update!(waba_id: "waba-selector-followup")
    lead = create(:lead, tenant: tenant)
    conversation = WhatsappConversation.create!(tenant: tenant, lead: lead, contact_phone: "5547999990202")
    conversation.messages.create!(tenant: tenant, direction: "inbound", body: "Tenho interesse", status: "delivered")
    approve_template(tenant: tenant, integration: integration, name: "lead_followup")

    result = described_class.call(conversation: conversation, admin_user: admin)

    expect(result.template.name).to eq("lead_followup")
    expect(result.label).to eq("Usar retomada de conversa")
  end

  it "cai para apresentacao oficial quando nao ha template de cenario aprovado" do
    tenant = Tenant.create!(name: "Fallback", slug: "selector-fallback-#{SecureRandom.hex(3)}")
    admin = create(:admin_user, tenant: tenant)
    integration = WhatsappBusinessIntegration.current(tenant)
    integration.update!(waba_id: "waba-selector-fallback")
    lead = create(:lead, tenant: tenant)
    conversation = WhatsappConversation.create!(tenant: tenant, lead: lead, contact_phone: "5547999990203")
    WhatsappTemplate.create!(
      tenant: tenant,
      waba_id: integration.waba_id,
      name: Whatsapp::LeadActivationTemplate::TEMPLATE_NAME,
      language: "pt_BR",
      status: "APPROVED",
      category: "MARKETING",
      template_type: "text",
      header_format: "none",
      body: Whatsapp::LeadActivationTemplate::DEFAULT_BODY
    )

    result = described_class.call(conversation: conversation, admin_user: admin)

    expect(result.template.name).to eq(Whatsapp::LeadActivationTemplate::TEMPLATE_NAME)
    expect(result.label).to eq("Usar apresentação oficial")
  end
end

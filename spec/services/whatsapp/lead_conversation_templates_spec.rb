require "rails_helper"

RSpec.describe Whatsapp::LeadConversationTemplates do
  describe ".for" do
    it "monta os templates oficiais de conversa sem cabecalho, midia ou botoes" do
      tenant = Tenant.create!(name: "Conexão Imobiliária", slug: "conv-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-conversation")

      templates = described_class.names.map { |name| described_class.for(tenant: tenant, integration: integration, name: name) }

      expect(templates.map(&:name)).to eq(["lead_followup", "lead_appointment_reminder", "lead_task_reminder_utility"])
      expect(templates.map(&:language).uniq).to eq(["pt_BR"])
      expect(templates.map(&:header_format).uniq).to eq(["none"])
      expect(templates.flat_map(&:clean_buttons)).to be_empty
      expect(templates.map(&:variable_count)).to eq([4, 5, 4])
    end

    it "monta payload Meta com corpo e exemplos do template de agenda" do
      tenant = Tenant.create!(name: "Payload Imobiliária", slug: "payload-conv-#{SecureRandom.hex(3)}")
      integration = WhatsappBusinessIntegration.current(tenant)
      integration.update!(waba_id: "waba-payload-conv")
      template = described_class.for(tenant: tenant, integration: integration, name: "lead_appointment_reminder")
      template.status = "PENDING"

      expect(template.meta_create_payload).to include(
        name: "lead_appointment_reminder",
        language: "pt_BR",
        category: "UTILITY"
      )
      expect(template.meta_create_payload[:components]).to eq([
        {
          type: "BODY",
          text: described_class.find("lead_appointment_reminder").body,
          example: { body_text: [described_class.find("lead_appointment_reminder").example_values] }
        }
      ])
    end
  end

  describe ".variable_values" do
    it "usa dados da agenda quando o template é de compromisso" do
      tenant = Tenant.create!(name: "Agenda Imóveis", slug: "agenda-#{SecureRandom.hex(3)}")
      admin = create(:admin_user, tenant: tenant, name: "Karla")
      lead = create(:lead, tenant: tenant, name: "Maria")
      conversation = WhatsappConversation.create!(tenant: tenant, lead: lead, contact_phone: "5547999990101")
      starts_at = 2.days.from_now.change(hour: 15, min: 30, sec: 0)
      Appointment.create!(
        tenant: tenant,
        lead: lead,
        admin_user: admin,
        title: "Visita ao apartamento",
        kind: "visita",
        starts_at: starts_at,
        status: "agendado"
      )

      values = described_class.variable_values(name: "lead_appointment_reminder", conversation: conversation, admin_user: admin)

      expect(values).to include(
        "1" => "Maria",
        "2" => "Karla",
        "3" => "Agenda Imóveis",
        "4" => I18n.l(starts_at, format: "%d/%m às %H:%M"),
        "5" => "Visita - Visita ao apartamento"
      )
    end

    it "usa dados da tarefa quando o template é de tarefa" do
      tenant = Tenant.create!(name: "Tarefas Imóveis", slug: "tarefas-#{SecureRandom.hex(3)}")
      admin = create(:admin_user, tenant: tenant, name: "Rafael")
      lead = create(:lead, tenant: tenant, name: "João")
      conversation = WhatsappConversation.create!(tenant: tenant, lead: lead, contact_phone: "5547999990102")
      create(:task, tenant: tenant, lead: lead, admin_user: admin, title: "retornar com proposta")

      values = described_class.variable_values(name: "lead_task_reminder_utility", conversation: conversation, admin_user: admin)

      expect(values).to include(
        "1" => "João",
        "2" => "Rafael",
        "3" => "Tarefas Imóveis",
        "4" => "retornar com proposta"
      )
    end
  end
end

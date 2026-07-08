require "rails_helper"

# Especifica o BRANCHING do resolver de transporte (tenant vs global vs nil)
# via doubles, sem depender das colunas/tabelas criadas pela frente migrations.
RSpec.describe Notifications::TransportResolver do
  describe ".whatsapp" do
    let(:tenant) { instance_double("Tenant") }

    it "usa a integracao manual/fixa do tenant para notificacoes do sistema (source :tenant)" do
      integration = instance_double(WhatsappBusinessIntegration, messaging_ready?: true)
      allow(WhatsappBusinessIntegration).to receive(:current).with(tenant).and_return(integration)

      result = described_class.whatsapp(tenant)

      expect(result.sender).to eq(integration)
      expect(result.source).to eq(:tenant)
      expect(result).to be_tenant
    end

    it "cai no sender GLOBAL quando o tenant e opt-in e o global esta configurado (source :global)" do
      integration = instance_double(WhatsappBusinessIntegration, messaging_ready?: false)
      allow(WhatsappBusinessIntegration).to receive(:current).with(tenant).and_return(integration)
      allow(tenant).to receive(:use_global_whatsapp_fallback?).and_return(true)

      system = instance_double(
        SystemNotificationSetting,
        whatsapp_configured?: true,
        whatsapp_access_token: "tok",
        whatsapp_phone_number_id: "123",
        whatsapp_business_account_id: "waba",
        whatsapp_template_name: "lead_global"
      )
      allow(SystemNotificationSetting).to receive(:instance).and_return(system)

      result = described_class.whatsapp(tenant)

      expect(result).to be_global
      expect(result.sender.access_token).to eq("tok")
      expect(result.sender.phone_number_id).to eq("123")
      expect(result.sender.template_name).to eq("lead_global")
    end

    it "retorna nil quando o tenant NAO e opt-in mesmo com global configurado" do
      integration = instance_double(WhatsappBusinessIntegration, messaging_ready?: false)
      allow(WhatsappBusinessIntegration).to receive(:current).with(tenant).and_return(integration)
      allow(tenant).to receive(:use_global_whatsapp_fallback?).and_return(false)

      expect(described_class.whatsapp(tenant)).to be_nil
    end

    it "retorna nil quando opt-in mas o global nao esta configurado" do
      integration = instance_double(WhatsappBusinessIntegration, messaging_ready?: false)
      allow(WhatsappBusinessIntegration).to receive(:current).with(tenant).and_return(integration)
      allow(tenant).to receive(:use_global_whatsapp_fallback?).and_return(true)
      allow(SystemNotificationSetting).to receive(:instance)
        .and_return(instance_double(SystemNotificationSetting, whatsapp_configured?: false))

      expect(described_class.whatsapp(tenant)).to be_nil
    end
  end

  describe ".email" do
    let(:tenant) { instance_double("Tenant", id: 7) }

    it "retorna nil quando nao ha SMTP disponivel" do
      allow(EmailSetting).to receive(:for).with(tenant).and_return(nil)

      expect(described_class.email(tenant)).to be_nil
    end
  end
end

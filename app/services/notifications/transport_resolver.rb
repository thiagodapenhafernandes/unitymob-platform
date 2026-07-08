module Notifications
  # Resolve o TRANSPORTE de notificação por conta (tenant), com fallback GLOBAL
  # opt-in do Admin do Sistema. NÃO resolve o ALVO (corretor/usuário) — só de
  # onde sai a mensagem. Deixa explícito se a origem é :tenant ou :global.
  #
  # Uso:
  #   sender = Notifications::TransportResolver.whatsapp(tenant)
  #   # => Notifications::TransportResolver::Result(sender:, source:) ou nil
  #   Whatsapp::CloudClient.new(sender.sender) if sender
  class TransportResolver
    Result = Struct.new(:sender, :source, keyword_init: true) do
      def tenant?
        source == :tenant
      end

      def global?
        source == :global
      end
    end

    # Sender GLOBAL de WhatsApp: mesma interface que o Whatsapp::CloudClient
    # consome da WhatsappBusinessIntegration (access_token / phone_number_id),
    # mais o template padrão do sistema.
    GlobalWhatsappSender = Struct.new(:access_token, :phone_number_id, :waba_id, :template_name, keyword_init: true)

    # WhatsApp: integração PRÓPRIA do tenant vence; senão, se a conta é opt-in E
    # a conta global do sistema está configurada, usa o sender global. Senão nil.
    def self.whatsapp(tenant)
      integration = WhatsappBusinessIntegration.current(tenant)
      return Result.new(sender: integration, source: :tenant) if integration&.messaging_ready?

      return nil unless tenant.respond_to?(:use_global_whatsapp_fallback?) && tenant&.use_global_whatsapp_fallback?

      system = SystemNotificationSetting.instance
      return nil unless system.whatsapp_configured?

      sender = GlobalWhatsappSender.new(
        access_token:    system.whatsapp_access_token,
        phone_number_id: system.whatsapp_phone_number_id,
        waba_id:         (system.whatsapp_business_account_id if system.respond_to?(:whatsapp_business_account_id)),
        template_name:   system.whatsapp_template_name.presence
      )
      Result.new(sender: sender, source: :global)
    end

    # E-mail: SMTP próprio do tenant, senão global opt-in configurado, senão nil.
    # A origem (:tenant/:global) é inferida do tenant_id do EmailSetting resolvido.
    def self.email(tenant)
      setting = EmailSetting.for(tenant)
      return nil unless setting

      source = email_source_for(setting, tenant)
      Result.new(sender: setting, source: source)
    end

    def self.email_source_for(setting, tenant)
      return :global unless setting.respond_to?(:tenant_id)
      return :global if setting.tenant_id.blank?

      tenant.present? && setting.tenant_id == tenant.id ? :tenant : :global
    end
    private_class_method :email_source_for
  end
end

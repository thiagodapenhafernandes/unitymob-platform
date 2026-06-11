module Leads
  # Dispara notificações pro corretor recém-atribuído, obedecendo as flags
  # da DistributionRule (notify_whatsapp, notify_email, notify_push,
  # notify_webhook). Chamado após o Lead ser vinculado a um admin_user.
  #
  # Todas as entregas são best-effort (erro em uma não bloqueia as outras).
  class NotificationDispatcher
    def self.deliver(lead)
      new(lead).deliver
    end

    def initialize(lead)
      @lead = lead
      @rule = lead.distribution_rule
      @corretor = lead.admin_user
    end

    def deliver
      return unless @rule && @corretor

      begin
        deliver_push if @rule.notify_push
      rescue => e
        Rails.logger.warn("[LeadNotify] push falhou: #{e.message}")
      end

      begin
        deliver_whatsapp if @rule.notify_whatsapp
      rescue => e
        Rails.logger.warn("[LeadNotify] whatsapp falhou: #{e.message}")
      end

      begin
        deliver_email if @rule.notify_email
      rescue => e
        Rails.logger.warn("[LeadNotify] email falhou: #{e.message}")
      end

      begin
        deliver_webhook if @rule.notify_webhook
      rescue => e
        Rails.logger.warn("[LeadNotify] webhook falhou: #{e.message}")
      end
    end

    private

    def deliver_push
      Notifications::PushDispatcher.deliver(
        admin_user_id: @corretor.id,
        title: "Novo lead: #{@lead.display_name}",
        body:  "#{@lead.display_phone} · Origem: #{@lead.origin}",
        url:   "/admin/leads/#{@lead.id}"
      )
    end

    def deliver_whatsapp
      setting = WebhookSetting.first
      return unless setting&.whatsapp_webhook_url.present?

      payload = {
        event: "lead.distributed",
        channel: "whatsapp",
        lead: lead_payload,
        corretor: corretor_payload,
        rule: rule_payload
      }

      WebhookService.send_form_data("lead_distributed", payload, url: setting.whatsapp_webhook_url)
    end

    def deliver_email
      # TODO: implementar LeadMailer quando houver config de email.
      Rails.logger.info("[LeadNotify] email pendente — mailer não configurado")
    end

    def deliver_webhook
      setting = WebhookSetting.first
      return unless setting&.webhook_url.present?

      payload = {
        event: "lead.distributed",
        channel: "webhook",
        lead: lead_payload,
        corretor: corretor_payload,
        rule: rule_payload
      }

      WebhookService.send_form_data("lead_distributed", payload)
    end

    def lead_payload
      {
        id: @lead.id,
        name: @lead.display_name,
        phone: @lead.display_phone,
        email: @lead.display_email,
        origin: @lead.origin,
        product: @lead.product,
        created_at: @lead.created_at&.iso8601
      }
    end

    def corretor_payload
      {
        id: @corretor.id,
        name: @corretor.name,
        phone: @corretor.phone,
        email: @corretor.email
      }
    end

    def rule_payload
      {
        id: @rule.id,
        name: @rule.name
      }
    end
  end
end

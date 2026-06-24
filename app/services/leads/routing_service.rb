module Leads
  class RoutingService
    def self.route!(lead)
      new(lead).route!
    end

    def initialize(lead)
      @lead = lead
    end

    def route!
      @lead.activities.create(kind: "received", metadata: { origin: @lead.origin })

      if @lead.admin_user_id.present?
        @lead.activities.create(kind: "assigned_directly", metadata: {
          admin_user_id: @lead.admin_user_id,
          reason: @lead.share_token.present? ? "share_link" : "manual_assignment"
        })
        Leads::NotificationDispatcher.notify_direct_assignment(@lead)
      else
        Leads::DistributorService.find_and_distribute(@lead)
      end

      # 2. Roteamento por E-mail (Sempre enviar se configurado)
      if email_enabled?
        dispatch_to_email
      end

      # 3. Roteamento por Webhook
      if webhook_enabled?
        dispatch_to_webhook
      end
    end

    private

    def email_enabled?
      Setting.get("lead_routing_email_enabled") == "true" &&
      Setting.get("lead_routing_emails_list").present?
    end

    def webhook_enabled?
      Setting.get("lead_routing_webhook_enabled") == "true" &&
      Setting.get("lead_routing_webhook_url").present?
    end

    def dispatch_to_email
      emails = Setting.get("lead_routing_emails_list").to_s.split(",").map(&:strip).reject(&:blank?)
      # Notificações via Email seriam feitas aqui via Mailer
      Rails.logger.info "Enviando lead #{@lead.id} para e-mails: #{emails.join(', ')}"
    end

    def dispatch_to_webhook
      url = Setting.get("lead_routing_webhook_url")
      # Leads::WebhookJob seria chamado aqui
      Rails.logger.info "Enviando lead #{@lead.id} para webhook: #{url}"
    end
  end
end

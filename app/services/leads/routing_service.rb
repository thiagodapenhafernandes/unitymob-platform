module Leads
  class RoutingService
    def self.route!(lead)
      new(lead).route!
    end

    def self.assign_shared_inquiry!(lead, inquiry)
      return false if inquiry.share_token.blank? || inquiry.property_id.blank?
      return false unless inquiry.admin_user_id.present? && inquiry.admin_user_id == inquiry.shared_by_admin_user_id
      link = HabitationShareLink.active.joins(:habitation, :admin_user)
        .where(habitations: { tenant_id: lead.tenant_id }, admin_users: { tenant_id: lead.tenant_id, active: true })
        .find_by(token: inquiry.share_token, habitation_id: inquiry.property_id, admin_user_id: inquiry.admin_user_id)
      return false unless link
      return false unless link.broker_page?

      # Uma conversão pelo link do corretor é atribuição explícita, inclusive na reentrada.
      lead.assign_attributes(admin_user_id: link.admin_user_id, shared_by_admin_user_id: link.admin_user_id,
        share_token: link.token, status: :waiting_acceptance, distribution_rule: nil,
        archived_at: nil, archived_by_admin_user: nil, archive_reason: nil, archive_note: nil,
        distribution_cycle_started_at: Time.current, contingency_forwarded_at: nil, contingency_pending: false,
        contingency_source_rule: nil, contingency_target_rule: nil, contingency_reason: nil)
      LeadActivity.log!(lead: lead, kind: "assigned_directly", metadata: {
        admin_user_id: link.admin_user_id, reason: "share_link", property_id: inquiry.property_id
      })
      true
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
      Setting.tenant_get("lead_routing_email_enabled", tenant: tenant) == "true" &&
      Setting.tenant_get("lead_routing_emails_list", tenant: tenant).present?
    end

    def webhook_enabled?
      Setting.tenant_get("lead_routing_webhook_enabled", tenant: tenant) == "true" &&
      Setting.tenant_get("lead_routing_webhook_url", tenant: tenant).present?
    end

    def dispatch_to_email
      emails = Setting.tenant_get("lead_routing_emails_list", tenant: tenant).to_s.split(",").map(&:strip).reject(&:blank?)
      # Notificações via Email seriam feitas aqui via Mailer
      Rails.logger.info "Enviando lead #{@lead.id} para e-mails: #{emails.join(', ')}"
    end

    def dispatch_to_webhook
      url = Setting.tenant_get("lead_routing_webhook_url", tenant: tenant)
      # Leads::WebhookJob seria chamado aqui
      Rails.logger.info "Enviando lead #{@lead.id} para webhook: #{url}"
    end

    def tenant
      @lead.tenant || Current.tenant || raise(ArgumentError, "Tenant obrigatório para roteamento de leads")
    end
  end
end

module Leads
  class InternalContactCleanup
    Result = Struct.new(:tenant_id, :tenant_name, :matched_count, :removed_count, :leads, keyword_init: true)
    NULLIFY_LEAD_REFERENCES = [
      AiPropertyShareAuditEvent,
      AiPropertyShareCollection,
      AutomationEvent,
      AutomationExecution,
      AutomationRun,
      AutomationWebhookDelivery,
      ClientPropertyInterest,
      PublicNavigationEvent,
      PublicNavigationSession,
      PushDeliveryEvent,
      SeoConversionEvent,
      WhatsappCampaignRecipient,
      WhatsappConversation,
      Appointment,
      Task
    ].freeze

    DELETE_LEAD_REFERENCES = [
      InstagramMessage
    ].freeze

    def self.call(tenant: nil, execute: false, logger: Rails.logger)
      new(tenant:, execute:, logger:).call
    end

    def initialize(tenant: nil, execute: false, logger: Rails.logger)
      @tenant = tenant
      @execute = execute
      @logger = logger
    end

    def call
      previous_tenant = Current.tenant
      tenants.map { |tenant| cleanup_tenant(tenant) }
    ensure
      Current.tenant = previous_tenant
    end

    private

    attr_reader :tenant, :execute, :logger

    def tenants
      return Array(tenant) if tenant.present?

      Tenant.order(:id)
    end

    def cleanup_tenant(tenant)
      leads = InternalContactScope.new(tenant: tenant).matching.order(:id).to_a
      removed = 0

      if execute && leads.any?
        leads.each do |lead|
          Current.tenant = tenant
          lead.transaction do
            clear_external_references(lead)
            lead.destroy!
          end
          removed += 1
        end
      end

      Result.new(
        tenant_id: tenant.id,
        tenant_name: tenant.name,
        matched_count: leads.size,
        removed_count: removed,
        leads: leads.map { |lead| lead_snapshot(lead) }
      )
    end

    def lead_snapshot(lead)
      {
        id: lead.id,
        name: lead.display_name.presence || lead.name,
        phone: lead.display_phone.presence || lead.phone,
        origin: lead.origin,
        admin_user_id: lead.admin_user_id,
        created_at: lead.created_at
      }
    end

    def clear_external_references(lead)
      NULLIFY_LEAD_REFERENCES.each do |model|
        next unless model.table_exists?

        model.where(lead_id: lead.id).update_all(lead_id: nil, updated_at: Time.current)
      end

      DELETE_LEAD_REFERENCES.each do |model|
        next unless model.table_exists?

        model.where(lead_id: lead.id).delete_all
      end
    end
  end
end

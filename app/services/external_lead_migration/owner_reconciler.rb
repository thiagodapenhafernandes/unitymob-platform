module ExternalLeadMigration
  class OwnerReconciler
    SOURCE = LeadMapper::PROVIDER_KEY
    Result = Struct.new(:scanned, :assigned, :skipped, :skipped_non_operational, :unmapped, keyword_init: true)

    def self.call(tenant: nil, integration: nil, execute: false, operational_only: false)
      new(tenant:, integration:, execute:, operational_only:).call
    end

    def initialize(tenant: nil, integration: nil, execute: false, operational_only: false)
      @tenant = integration&.tenant || tenant
      @integration = integration
      @execute = execute
      @operational_only = operational_only
      @result = Result.new(scanned: 0, assigned: 0, skipped: 0, skipped_non_operational: 0, unmapped: 0)
    end

    def call
      integrations.find_each do |current_integration|
        @integration = current_integration
        reconcile_integration
      end

      result
    end

    private

    attr_reader :tenant, :execute, :operational_only, :result
    attr_accessor :integration

    def integrations
      scope = ExternalLeadIntegration.where.not(id: nil)
      scope = scope.where(tenant_id: tenant.id) if tenant.present?
      scope = scope.where(id: integration.id) if integration.present?
      scope
    end

    def reconcile_integration
      lead_scope.find_each(batch_size: 500) do |lead|
        result.scanned += 1
        reconcile_lead(lead)
      end
    end

    def lead_scope
      integration.tenant.leads
        .where(external_lead_integration_id: integration.id, admin_user_id: nil)
        .where("other_information @> ?", { source: SOURCE }.to_json)
    end

    def reconcile_lead(lead)
      return skip_non_operational! if operational_only && !operational_lead?(lead)

      user = integration.local_user_for_seller(seller_from(lead))
      return unmapped! if user.blank?

      lead.update!(admin_user: user) if execute
      result.assigned += 1
    rescue ActiveRecord::RecordInvalid
      result.skipped += 1
    end

    def seller_from(lead)
      info = lead.other_information.to_h
      seller = info["external_lead_seller"].presence ||
        info.dig("external_lead_payload", "attributes", "seller").presence ||
        info.dig("data", "attributes", "seller").presence ||
        {}

      seller = seller.to_h
      seller["id"] ||= lead.agent_external_id
      seller["name"] ||= lead.agent_name
      seller["email"] ||= lead.agent_email
      seller["phone"] ||= lead.agent_phone
      seller
    end

    def operational_lead?(lead)
      return false if Lead.non_operational_status_values(tenant: lead.tenant).include?(lead.status)
      return false if lead.lead_pipeline_stage&.stage_type.in?(%w[won lost archived])

      true
    end

    def unmapped!
      result.unmapped += 1
    end

    def skip_non_operational!
      result.skipped_non_operational += 1
    end
  end
end

module ExternalLeadMigration
  class LeadUpsert
    Result = Struct.new(:lead, :action, keyword_init: true)

    def self.call(integration:, payload:, historical: false)
      new(integration:, payload:, historical:).call
    end

    def initialize(integration:, payload:, historical: false)
      @integration = integration
      @payload = payload
      @historical = historical
    end

    def call
      mapper = LeadMapper.new(payload)
      raise ArgumentError, "Payload externo sem ID do lead" if mapper.external_lead_id.blank?

      Current.set(tenant: integration.tenant) do
        attrs = mapper.lead_attributes(integration:, historical:)
        lead = find_existing(mapper)
        if lead
          action = :updated
          lead.with_lock do
            attrs.delete(:created_at)
            if lead.other_information["intake_reconciled"]
              attrs = attrs.slice(:external_last_synced_at, :other_information)
              attrs[:other_information] = lead.other_information.merge(attrs[:other_information] || {})
            end
            lead.skip_automatic_routing = historical || lead.other_information["intake_reconciled"]
            lead.update!(attrs)
          end
        else
          inquiry = integration.tenant.leads.new(attrs)
          inquiry.skip_automatic_routing = historical
          lead = Leads::Intake.receive!(inquiry)
          action = lead.intake_reused ? :updated : :created
        end
        lead.reload if should_use_local_assignment_for_enrichment?(lead:, attrs:)
        LeadEnrichment.call(lead:, integration:, mapper:, historical:)

        LeadActivity.log!(
          lead: lead,
          kind: historical ? "external_lead_imported" : "external_lead_synced",
          metadata: {
            external_lead_id: mapper.external_lead_id,
            external_internal_id: mapper.external_internal_id,
            action: action,
            event_name: attrs[:event_name],
            mirrored_admin_user_id: attrs[:admin_user]&.id
          }.compact
        )

        Result.new(lead:, action:)
      end
    rescue ActiveRecord::RecordNotUnique
      retry_lead = integration.tenant.leads.find_by(external_lead_id: LeadMapper.new(payload).external_lead_id)
      Result.new(lead: retry_lead, action: :duplicate)
    end

    private

    attr_reader :integration, :payload, :historical

    def find_existing(mapper)
      integration.tenant.leads.find_by(external_lead_id: mapper.external_lead_id) ||
        Leads::Intake.find_received_event(tenant: integration.tenant, reference: "c2s:#{mapper.external_lead_id}")
    end

    def should_use_local_assignment_for_enrichment?(lead:, attrs:)
      !historical && attrs[:admin_user].blank? && lead.admin_user_id.blank?
    end
  end
end

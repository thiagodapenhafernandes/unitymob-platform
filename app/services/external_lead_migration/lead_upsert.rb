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
        mirror = integration.mirror_c2s_owners?
        lead = find_existing(mapper, mirror:)
        if lead
          action = :updated
          lead.with_lock do
            previous_owner_id = lead.admin_user_id
            if mirror && stale_mirror_payload?(lead, mapper)
              return Result.new(lead:, action: :stale)
            end
            mirror_owner = MirrorSeller.call(integration:, seller: mapper.seller) if mirror
            attrs.delete(:created_at)
            attrs.except!(:admin_user, :distribution_rule) unless historical
            if lead.other_information["intake_reconciled"]
              attrs = attrs.slice(:external_last_synced_at, :other_information)
              attrs[:other_information] = lead.other_information.merge(attrs[:other_information] || {})
            elsif lead.other_information["c2s_assignment_decided"]
              attrs.except!(:admin_user, :distribution_rule, :status, :lead_pipeline, :lead_pipeline_stage)
              attrs[:other_information] = lead.other_information.merge(attrs[:other_information] || {})
            end
            if mirror
              attrs = attrs.slice(:external_last_synced_at, :other_information)
              attrs[:admin_user] = mirror_owner
              attrs[:distribution_rule] = nil
              attrs[:other_information] = lead.other_information.merge(attrs[:other_information] || {})
              attrs[:other_information]["c2s_owner_source_updated_at"] = mapper.source_updated_at&.iso8601
            end
            lead.skip_automatic_routing = true
            lead.update!(attrs)
            if mirror && previous_owner_id != lead.admin_user_id
              lead.activities.create!(kind: "external_owner_mirrored", source_category: "external_sync", metadata: {
                previous_admin_user_id: previous_owner_id, admin_user_id: lead.admin_user_id,
                external_lead_id: mapper.external_lead_id, source_updated_at: mapper.source_updated_at&.iso8601
              }.compact)
            end
          end
        else
          if mirror
            attrs[:admin_user] = MirrorSeller.call(integration:, seller: mapper.seller)
            attrs[:distribution_rule] = nil
          end
          inquiry = integration.tenant.leads.new(attrs)
          inquiry.skip_automatic_routing = historical || mirror
          if mirror
            inquiry.other_information["c2s_owner_source_updated_at"] = mapper.source_updated_at&.iso8601
            inquiry.save!
            lead = inquiry
          else
            lead = Leads::Intake.receive!(inquiry)
          end
          action = lead.intake_reused ? :updated : :created
        end
        lead.reload if should_use_local_assignment_for_enrichment?(lead:, attrs:)
        if mirror
          lead.with_lock do
            return Result.new(lead:, action: :stale) if stale_mirror_payload?(lead, mapper)

            LeadEnrichment.call(lead:, integration:, mapper:, historical:)
          end
        else
          LeadEnrichment.call(lead:, integration:, mapper:, historical:)
        end

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

    def stale_mirror_payload?(lead, mapper)
      stamp = lead.other_information["c2s_owner_source_updated_at"].presence
      stamp && (!mapper.source_updated_at || mapper.source_updated_at < Time.iso8601(stamp))
    end

    def find_existing(mapper, mirror: false)
      direct = integration.tenant.leads.find_by(external_lead_id: mapper.external_lead_id) ||
        integration.tenant.leads.find_by(c2s_export_external_id: mapper.external_lead_id)
      return direct if direct || mirror

      Leads::Intake.find_received_event(tenant: integration.tenant, reference: "c2s:#{mapper.external_lead_id}")
    end

    def should_use_local_assignment_for_enrichment?(lead:, attrs:)
      !historical && attrs[:admin_user].blank? && lead.admin_user_id.blank?
    end
  end
end

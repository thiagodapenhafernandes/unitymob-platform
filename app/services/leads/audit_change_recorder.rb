module Leads
  class AuditChangeRecorder
    AUDITED_FIELDS = %w[
      name email phone client_name client_email client_phone status notes origin lead_type
      property_id admin_user_id distribution_rule_id source_url product custom_answers other_information
    ].freeze

    IGNORED_FIELDS = %w[id created_at updated_at share_token].freeze

    def self.record_create!(lead)
      new(lead).record_create!
    end

    def self.record_update!(lead)
      new(lead).record_update!
    end

    def self.record_destroy!(lead)
      new(lead).record_destroy!
    end

    def initialize(lead)
      @lead = lead
    end

    def record_create!
      LeadAuditLog.create!(
        lead_id: lead.id,
        admin_user: Current.admin_user,
        action: "created",
        source: infer_create_source,
        changed_fields: create_changeset.keys,
        changeset: create_changeset,
        metadata: metadata,
        ip: Current.request_ip,
        user_agent: Current.request_user_agent
      )
    rescue => e
      Rails.logger.warn("[LeadAuditLog] create #{e.class}: #{e.message}")
      nil
    end

    def record_update!
      changeset = normalized_changes
      return if changeset.blank?

      LeadAuditLog.create!(
        lead_id: lead.id,
        admin_user: Current.admin_user,
        action: infer_update_action(changeset),
        source: infer_update_source(changeset),
        changed_fields: changeset.keys,
        changeset: changeset,
        metadata: metadata,
        ip: Current.request_ip,
        user_agent: Current.request_user_agent
      )
    rescue => e
      Rails.logger.warn("[LeadAuditLog] update #{e.class}: #{e.message}")
      nil
    end

    def record_destroy!
      LeadAuditLog.create!(
        lead_id: lead.id,
        admin_user: Current.admin_user,
        action: "deleted",
        source: Current.admin_user.present? ? "admin" : "system",
        changed_fields: AUDITED_FIELDS,
        changeset: destroy_changeset,
        metadata: metadata,
        ip: Current.request_ip,
        user_agent: Current.request_user_agent
      )
    rescue => e
      Rails.logger.warn("[LeadAuditLog] destroy #{e.class}: #{e.message}")
      nil
    end

    private

    attr_reader :lead

    def create_changeset
      lead.attributes.slice(*AUDITED_FIELDS).compact_blank.transform_values { |value| { before: nil, after: normalize_value(value) } }
    end

    def normalized_changes
      lead.previous_changes.each_with_object({}) do |(field, values), result|
        next if IGNORED_FIELDS.include?(field.to_s)
        next unless AUDITED_FIELDS.include?(field.to_s)

        before, after = values
        next if before == after

        result[field.to_s] = { before: normalize_value(before), after: normalize_value(after) }
      end
    end

    def destroy_changeset
      lead.attributes.slice(*AUDITED_FIELDS).compact_blank.transform_values { |value| { before: normalize_value(value), after: nil } }
    end

    def normalize_value(value)
      case value
      when Time, Date, DateTime
        value.iso8601
      else
        value
      end
    end

    def infer_update_action(changeset)
      return "assigned" if changeset.key?("admin_user_id")
      return "status_changed" if changeset.key?("status")

      "updated"
    end

    def infer_create_source
      return "admin" if Current.admin_user.present?
      return "meta" if lead.origin.to_s.match?(/meta|facebook/i) || lead.source_url.to_s.match?(/facebook|meta/i)
      return "site" if lead.source_url.present? || lead.origin.to_s.match?(/site|whatsapp|form/i)

      "system"
    end

    def infer_update_source(changeset)
      return "admin" if Current.admin_user.present?
      return "distribution" if (changeset.keys & %w[admin_user_id distribution_rule_id status]).any?

      "system"
    end

    def metadata
      (Current.request_metadata || {}).compact
    end
  end
end

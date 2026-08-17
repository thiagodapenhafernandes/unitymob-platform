module ExternalLeadMigration
  class LabelReconciler
    SOURCE = LeadMapper::PROVIDER_KEY
    Result = Struct.new(:scanned, :labels_created, :labelings_created, :skipped, keyword_init: true)

    def self.call(tenant: nil, integration: nil, execute: false)
      new(tenant:, integration:, execute:).call
    end

    def initialize(tenant: nil, integration: nil, execute: false)
      @tenant = integration&.tenant || tenant
      @integration = integration
      @execute = execute
      @result = Result.new(scanned: 0, labels_created: 0, labelings_created: 0, skipped: 0)
      @planned_labels = {}
      @planned_labelings = {}
    end

    def call
      leads.find_each(batch_size: 500) do |lead|
        result.scanned += 1
        reconcile_lead(lead)
      end

      result
    end

    private

    attr_reader :tenant, :integration, :execute, :result

    def leads
      scope = Lead.where(origin: ExternalLeadIntegration::LEAD_ORIGIN)
      scope = scope.where(tenant_id: tenant.id) if tenant.present?
      scope = scope.where(external_lead_integration_id: integration.id) if integration.present?
      scope
    end

    def reconcile_lead(lead)
      admin_user = lead.admin_user
      names = label_names_for(lead)
      return skip! if admin_user.blank? || names.blank?

      names.each { |name| reconcile_label(lead, admin_user, name) }
    end

    def reconcile_label(lead, admin_user, name)
      label = admin_user.lead_labels.find_by("LOWER(name) = ?", name.downcase)
      if label.blank?
        label_key = [admin_user.id, name.downcase]
        unless @planned_labels[label_key]
          @planned_labels[label_key] = true
          result.labels_created += 1
        end
        if execute
          label = admin_user.lead_labels.create!(
            tenant: lead.tenant,
            name: name,
            color: "gray"
          )
        end
      end

      labeling_key = [lead.id, label&.id || name.downcase]
      return if @planned_labelings[labeling_key]
      return if label.present? && lead.lead_labelings.exists?(lead_label: label)

      @planned_labelings[labeling_key] = true
      result.labelings_created += 1
      lead.lead_labelings.create!(tenant: lead.tenant, lead_label: label) if execute && label.present?
    end

    def label_names_for(lead)
      info = lead.other_information.is_a?(Hash) ? lead.other_information : {}
      payload = info["external_lead_payload"].is_a?(Hash) ? info["external_lead_payload"] : info
      attributes = payload["attributes"].is_a?(Hash) ? payload["attributes"] : {}
      tags = attributes["tags"].presence || payload["tags"]

      Array.wrap(tags)
        .filter_map { |item| item.is_a?(Hash) ? item["name"].presence || item["tag_name"] : item }
        .flat_map { |item| item.to_s.split(",") }
        .map { |item| item.strip.gsub(/\s+/, " ") }
        .reject(&:blank?)
        .reject { |item| technical_tag?(item) }
        .uniq
    end

    def technical_tag?(value)
      normalized = value.to_s.parameterize(separator: "_")
      [
        SOURCE,
        ExternalLeadIntegration::WEBHOOK_TAG,
        ExternalLeadIntegration::LEAD_ORIGIN
      ].map { |item| item.to_s.parameterize(separator: "_") }.include?(normalized)
    end

    def skip!
      result.skipped += 1
    end
  end
end

module Instagram
  class DecisionAudit
    def self.record(lead, message_id:, outcome:, **details)
      return unless lead.persisted? && message_id
      LeadActivity.transaction(requires_new: true) do
        lead.activities.create!(tenant: lead.tenant, kind: "instagram_sdr_decision", source_category: "automation",
          metadata: {message_id: message_id, outcome: outcome, version: 2}.merge(details))
      end
    rescue StandardError => error
      Rails.logger.warn("[Instagram SDR audit] error_class=#{error.class.name}")
      nil
    end
  end
end

module InterestIntelligence
  class ReprocessJob < ApplicationJob
    queue_as :default

    def perform(lead_id)
      lead = Lead.find_by(id: lead_id)
      return unless lead

      InterestIntelligence::Reprocessor.call(lead: lead, idempotency_scope: "auto")
    end
  end
end

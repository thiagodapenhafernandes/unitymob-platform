module Leads
  class PocketExpirationJob < ApplicationJob
    queue_as :default

    def perform(lead_id, expected_admin_user_id = nil)
      lead = Lead.find_by(id: lead_id)
      result = Leads::PocketExpirationService.expire!(
        lead,
        expected_admin_user_id: expected_admin_user_id,
        source: "scheduled"
      )

      Rails.logger.info "[PocketExpirationJob] lead=#{lead_id} result=#{result}"
    end
  end
end

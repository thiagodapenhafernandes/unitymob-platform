module PropertyReviewPolicy
  class ImpactReport
    TRACKED_STATUSES = %w[draft returned_to_broker submitted_for_admin_review admin_approved internal].freeze

    def self.call(tenant:, setting:)
      scope = tenant.habitations.broker_intakes.where(intake_status: TRACKED_STATUSES)
      by_status = scope.group(:intake_status).count
      {
        "in_progress" => by_status.values.sum,
        "by_status" => by_status,
        "awaiting_review" => by_status["submitted_for_admin_review"].to_i,
        "returned_to_broker" => by_status["returned_to_broker"].to_i,
        "ready_to_publish" => by_status["admin_approved"].to_i,
        "would_reassign_if_review_disabled" => setting.broker_capture_layer_enabled? ? scope.where.not(admin_user_id: setting.broker_capture_fallback_admin_user_id).count : 0
      }
    end
  end
end

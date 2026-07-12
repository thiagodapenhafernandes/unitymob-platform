module PropertyReviewPolicy
  class ProposalReport
    WORKFLOW_STAGE_FIELDS = %w[
      broker_capture_layer_enabled
      broker_capture_fallback_admin_user_id
      required_broker_intake_checks
      returnable_intake_edit_sections
    ].freeze

    FIELD_LABELS = {
      "broker_capture_layer_enabled" => "Aprovação administrativa",
      "broker_capture_fallback_admin_user_id" => "Responsável de contingência",
      "notify_internal_review_events" => "Notificação interna",
      "notify_email_review_events" => "Notificação por e-mail",
      "review_notification_emails" => "Destinatários de e-mail",
      "required_broker_intake_checks" => "Checklist de submissão",
      "returnable_intake_edit_sections" => "Blocos reabertos na devolução"
    }.freeze

    def self.call(before_snapshot:, proposed_setting:, impact_snapshot:)
      after_snapshot = ChangeRecorder.snapshot(proposed_setting)
      changes = before_snapshot.filter_map do |field, before_value|
        after_value = after_snapshot[field]
        next if before_value == after_value

        { "field" => field, "label" => FIELD_LABELS[field] || field.humanize, "before" => before_value, "after" => after_value }
      end
      confirmation_reasons = confirmation_reasons(changes, before_snapshot, after_snapshot, impact_snapshot)
      {
        "changes" => changes,
        "impact" => impact_snapshot,
        "operational_confirmation_reasons" => confirmation_reasons,
        "requires_operational_confirmation" => confirmation_reasons.present?
      }
    end

    def self.confirmation_reasons(changes, before_snapshot, after_snapshot, impact_snapshot)
      reasons = []
      if disabling_review?(before_snapshot, after_snapshot) && impact_snapshot["would_reassign_if_review_disabled"].to_i.positive?
        reasons << "reassign_in_progress"
      end

      changed_fields = changes.pluck("field")
      if (changed_fields & WORKFLOW_STAGE_FIELDS).any? && impact_snapshot["legacy_without_policy_snapshot"].to_i.positive?
        reasons << "affect_legacy_without_snapshot"
      end
      reasons
    end
    private_class_method :confirmation_reasons

    def self.disabling_review?(before_snapshot, after_snapshot)
      ActiveModel::Type::Boolean.new.cast(before_snapshot["broker_capture_layer_enabled"]) &&
        !ActiveModel::Type::Boolean.new.cast(after_snapshot["broker_capture_layer_enabled"])
    end
    private_class_method :disabling_review?
  end
end

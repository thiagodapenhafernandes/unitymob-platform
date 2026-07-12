module PropertyReviewPolicy
  class ProposalReport
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
      {
        "changes" => changes,
        "impact" => impact_snapshot,
        "requires_operational_confirmation" => disabling_review?(before_snapshot, after_snapshot) && impact_snapshot["would_reassign_if_review_disabled"].to_i.positive?
      }
    end

    def self.disabling_review?(before_snapshot, after_snapshot)
      ActiveModel::Type::Boolean.new.cast(before_snapshot["broker_capture_layer_enabled"]) &&
        !ActiveModel::Type::Boolean.new.cast(after_snapshot["broker_capture_layer_enabled"])
    end
    private_class_method :disabling_review?
  end
end

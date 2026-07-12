module PropertyReviewPolicy
  class ChangeRecorder
    TRACKED_FIELDS = %w[
      broker_capture_layer_enabled broker_capture_fallback_admin_user_id
      notify_internal_review_events notify_email_review_events review_notification_emails
      required_broker_intake_checks returnable_intake_edit_sections
    ].freeze

    def self.snapshot(setting)
      setting.attributes.slice(*TRACKED_FIELDS)
    end

    def self.call(setting:, admin_user:, before_snapshot:, impact_snapshot:)
      after_snapshot = snapshot(setting)
      changeset = before_snapshot.each_with_object({}) do |(field, before_value), result|
        after_value = after_snapshot[field]
        result[field] = { "before" => before_value, "after" => after_value } unless before_value == after_value
      end
      return if changeset.empty?

      setting.increment!(:review_policy_version)
      PropertyReviewPolicyAuditLog.create!(tenant: setting.tenant, property_setting: setting, admin_user: admin_user, version: setting.review_policy_version, changeset: changeset, impact_snapshot: impact_snapshot)
    end
  end
end

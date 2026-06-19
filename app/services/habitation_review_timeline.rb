class HabitationReviewTimeline
  REVIEW_RELEVANT_FIELDS = %w[
    intake_status
    admin_review_notes
    admin_review_return_reason
    admin_reviewed_by_id
    admin_reviewed_at
    admin_reviewed_by
  ].freeze

  def initialize(habitation:, limit: 20)
    @habitation = habitation
    @limit = limit.to_i.positive? ? limit.to_i : 20
  end

  def call
    return [] if @habitation.blank?

    logs = @habitation.habitation_audit_logs
      .includes(:admin_user)
      .order(created_at: :asc)

    version = 0
    timeline = []

    logs.each do |log|
      summaries = review_summaries(log)
      next if summaries.blank?

      version += 1 if review_status_changed?(log)
      timeline << {
        log: log,
        version: [version, 1].max,
        summaries: summaries
      }
    end

    timeline.reverse.take(@limit)
  end

  private

  def review_summaries(log)
    return [] unless review_relevant_changes?(log)

    Array(log.change_summaries).select do |summary|
      review_field?(summary[:field])
    end
  end

  def review_field?(field)
    REVIEW_RELEVANT_FIELDS.include?(field.to_s)
  end

  def review_relevant_changes?(log)
    return false unless log.changeset.is_a?(Hash)

    changes = log.changeset.keys.map(&:to_s)
    changes.any? { |field| review_field?(field) }
  end

  def review_status_changed?(log)
    return false unless log.changeset.is_a?(Hash)

    intake_status = log.changeset["intake_status"] || log.changeset[:intake_status]
    return false unless intake_status.is_a?(Hash) || intake_status.is_a?(ActionController::Parameters)

    before = intake_status["before"] || intake_status[:before]
    after = intake_status["after"] || intake_status[:after]
    before != after
  end
end

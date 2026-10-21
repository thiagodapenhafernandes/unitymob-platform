class GoogleStageConversionRecoveryJob < ApplicationJob
  queue_as :default

  def perform
    GoogleStageConversionEvent.where(status: "pending").where("next_attempt_at IS NULL OR next_attempt_at <= ?", Time.current)
      .where("created_at < ?", 1.minute.ago).find_each(&:enqueue_delivery)
  end
end

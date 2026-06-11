class LoftScheduleTickJob < ApplicationJob
  queue_as :default

  def perform
    result = Loft::ScheduledSyncService.new.call
    Rails.logger.info("[LoftScheduleTickJob] #{result[:status]} - #{result[:message]}")
  end
end

# Retenção do rastreador interno de erros (agendado em config/recurring.yml).
class ErrorEventsCleanupJob < ApplicationJob
  queue_as :default

  UNRESOLVED_RETENTION_DAYS = 90
  RESOLVED_RETENTION_DAYS = 1
  BATCH_SIZE = 5_000

  def perform
    return unless ErrorEvent.storage_ready?

    resolved_deleted = delete_resolved
    stale_deleted = delete_stale_unresolved

    Rails.logger.info(
      "[ERROR_TRACKER] retenção: #{resolved_deleted} resolvidos removidos " \
      "(resolved_at > #{RESOLVED_RETENTION_DAYS} dia); " \
      "#{stale_deleted} abertos antigos removidos " \
      "(last_seen_at > #{UNRESOLVED_RETENTION_DAYS} dias)"
    )
  end

  private

  def delete_resolved
    delete_count(
      ErrorEvent.resolved.where("resolved_at < ?", RESOLVED_RETENTION_DAYS.days.ago)
    )
  end

  def delete_stale_unresolved
    delete_count(
      ErrorEvent.unresolved.where("last_seen_at < ?", UNRESOLVED_RETENTION_DAYS.days.ago)
    )
  end

  def delete_count(scope)
    deleted = 0
    scope.in_batches(of: BATCH_SIZE) { |batch| deleted += batch.delete_all }
    deleted
  end
end

# Retenção do rastreador interno de erros (agendado em config/recurring.yml):
# apaga eventos sem ocorrência nova há mais de RETENTION_DAYS dias, em lotes.
class ErrorEventsCleanupJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS = 90
  BATCH_SIZE = 5_000

  def perform
    return unless ErrorEvent.storage_ready?

    cutoff = RETENTION_DAYS.days.ago
    deleted = 0
    ErrorEvent.where("last_seen_at < ?", cutoff).in_batches(of: BATCH_SIZE) do |batch|
      deleted += batch.delete_all
    end

    Rails.logger.info("[ERROR_TRACKER] retenção: #{deleted} eventos removidos (last_seen_at > #{RETENTION_DAYS} dias)")
  end
end

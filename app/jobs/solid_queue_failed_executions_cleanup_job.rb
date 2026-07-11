# frozen_string_literal: true

# Mantém detalhes de falhas recentes para diagnóstico sem deixar jobs e
# backtraces históricos crescerem indefinidamente. ErrorEvent preserva a visão
# agregada por 90 dias; a fila retém o detalhe operacional por uma janela menor.
class SolidQueueFailedExecutionsCleanupJob < ApplicationJob
  queue_as :checkin

  RETENTION_DAYS = ENV.fetch("SOLID_QUEUE_FAILED_RETENTION_DAYS", "14").to_i.clamp(7, 90)
  BATCH_SIZE = ENV.fetch("SOLID_QUEUE_FAILED_CLEANUP_BATCH_SIZE", "250").to_i.clamp(50, 1_000)

  def perform
    scope = SolidQueue::FailedExecution.where(created_at: ...RETENTION_DAYS.days.ago)
    removed = 0

    loop do
      job_ids = scope.order(:job_id).limit(BATCH_SIZE).pluck(:job_id)
      break if job_ids.empty?

      SolidQueue::FailedExecution.where(job_id: job_ids).discard_all_in_batches(batch_size: BATCH_SIZE)
      removed += job_ids.size
      sleep(0.05) if job_ids.size == BATCH_SIZE
    end

    Rails.logger.info("[SolidQueueCleanup] removed=#{removed} retention_days=#{RETENTION_DAYS}")
  end
end

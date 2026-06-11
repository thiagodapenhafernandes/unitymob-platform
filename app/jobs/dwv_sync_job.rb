class DwvSyncJob < ApplicationJob
  queue_as :dwv
  queue_with_priority(-10)

  def perform(mode: "full", limit: nil, max_pages: nil, triggered_by_id: nil)
    status_service = Dwv::SyncStatusService.new
    lock_service = Dwv::SyncLockService.new(lease_seconds: ENV.fetch("DWV_SYNC_LOCK_LEASE_SECONDS", "5400"))
    lock_owner = lock_service.acquire

    unless lock_owner.present?
      status_service.mark_skipped!(
        mode: mode,
        message: "DWV sync ignorado: já existe uma sincronização em andamento."
      )
      return
    end

    runner = Dwv::SyncRunnerService.new
    dedup_result = nil
    if mode.to_s.in?(%w[full batch])
      dedup_result = Dwv::DeduplicateHabitationLinksService.new.call!
    end

    result = runner.call(mode: mode, limit: limit, max_pages: max_pages, status_service: status_service)
    errors_by_reason = result[:errors_by_reason].is_a?(Hash) ? result[:errors_by_reason] : {}
    top_error = errors_by_reason.first

    message = [
      "DWV sync (#{mode}) concluído",
      "importados=#{result[:imported]}",
      "desativados=#{result[:deactivated]}",
      "erros=#{result[:errors_count]}",
      ("dedup_grupos=#{dedup_result[:duplicate_groups]} | dedup_desvinculados=#{dedup_result[:detached]}" if dedup_result.present?),
      ("top_erro=#{top_error[1]}x #{top_error[0]}" if top_error.present?),
      ("triggered_by=#{triggered_by_id}" if triggered_by_id.present?)
    ].compact.join(" | ")

    Setting.set("dwv_last_error_summary", errors_by_reason.to_json, "Resumo dos erros por tipo da última sincronização DWV")
    status_service.mark_completed!(mode: mode, message: message)
  rescue => e
    Setting.set("dwv_last_error_summary", {}.to_json, "Resumo dos erros por tipo da última sincronização DWV")
    status_service&.mark_failed!(mode: mode, message: "DWV sync (#{mode}) falhou: #{e.message}")
    raise e
  ensure
    lock_service&.release(lock_owner)
  end
end

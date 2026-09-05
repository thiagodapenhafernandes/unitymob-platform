module Loft
  class SyncStatusService < Integrations::SyncStatus
    PREFIX = "loft".freeze
    LABEL = "Loft".freeze
    HISTORY_KEY = "loft_sync_history".freeze
    PROGRESS_DESCRIPTION = "Progresso da sincronização Loft".freeze
    INCLUDE_STATS = true

    def mark_completed!(message:, mode: nil, stats: {})
      write_status("completed", message: message, mode: mode, progress: 100, stats: stats)
    end

    def mark_failed!(message:, mode: nil, stats: {})
      write_status("failed", message: message, mode: mode, stats: stats)
    end
  end
end

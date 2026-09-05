module Dwv
  class SyncStatusService < Integrations::SyncStatus
    PREFIX = "dwv".freeze
    LABEL = "DWV".freeze
    HISTORY_KEY = "dwv_sync_history".freeze
    PROGRESS_DESCRIPTION = "Progresso percentual da sincronização DWV".freeze
    INCLUDE_STATS = false

    def mark_completed!(message:, mode: nil)
      write_status("completed", message: message, mode: mode, progress: 100)
    end

    def mark_failed!(message:, mode: nil)
      write_status("failed", message: message, mode: mode)
    end
  end
end

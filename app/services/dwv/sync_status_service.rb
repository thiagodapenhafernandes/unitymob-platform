module Dwv
  class SyncStatusService
    HISTORY_KEY = "dwv_sync_history".freeze

    def initialize(tenant: Current.tenant)
      @tenant = tenant
    end

    def mark_processing!(message:, mode: nil, progress: 0)
      setting_set("dwv_sync_status", "processing", "Status da sincronização DWV")
      setting_set("dwv_sync_progress", progress.to_i.clamp(0, 100).to_s, "Progresso percentual da sincronização DWV")
      setting_set("dwv_last_sync_message", message.to_s, "Resumo da última execução DWV")
      append_history!(status: "processing", message: message, mode: mode)
    end

    def update_progress!(progress:, message: nil)
      setting_set("dwv_sync_progress", progress.to_i.clamp(0, 100).to_s, "Progresso percentual da sincronização DWV")
      setting_set("dwv_last_sync_message", message.to_s, "Resumo da última execução DWV") if message.present?
    end

    def mark_completed!(message:, mode: nil)
      stamp_last_sync_time!
      setting_set("dwv_sync_status", "completed", "Status da sincronização DWV")
      setting_set("dwv_sync_progress", "100", "Progresso percentual da sincronização DWV")
      setting_set("dwv_last_sync_message", message.to_s, "Resumo da última execução DWV")
      append_history!(status: "completed", message: message, mode: mode)
    end

    def mark_failed!(message:, mode: nil)
      stamp_last_sync_time!
      setting_set("dwv_sync_status", "failed", "Status da sincronização DWV")
      setting_set("dwv_last_sync_message", message.to_s, "Resumo da última execução DWV")
      append_history!(status: "failed", message: message, mode: mode)
    end

    def mark_skipped!(message:, mode: nil)
      stamp_last_sync_time!
      setting_set("dwv_sync_status", "skipped", "Status da sincronização DWV")
      setting_set("dwv_last_sync_message", message.to_s, "Resumo da última execução DWV")
      append_history!(status: "skipped", message: message, mode: mode)
    end

    def history(limit: 5)
      parse_history.first(limit)
    end

    private

    def append_history!(status:, message:, mode:)
      entries = parse_history
      entries.unshift(
        {
          "at" => Time.current.iso8601,
          "status" => status.to_s,
          "mode" => mode.to_s.presence,
          "message" => message.to_s
        }
      )
      setting_set(HISTORY_KEY, entries.first(5).to_json, "Histórico das últimas sincronizações DWV")
    end

    def parse_history
      raw = setting_get(HISTORY_KEY, "[]")
      parsed = JSON.parse(raw.to_s)
      return parsed if parsed.is_a?(Array)

      []
    rescue JSON::ParserError
      []
    end

    def stamp_last_sync_time!
      setting_set("dwv_last_sync_at", Time.current.iso8601, "Última execução DWV")
    end

    def setting_get(key, default = nil)
      Setting.tenant_get(key, default, tenant: @tenant)
    end

    def setting_set(key, value, description)
      Setting.set(key, value, description, tenant: @tenant)
    end
  end
end

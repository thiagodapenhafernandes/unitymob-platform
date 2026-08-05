module Loft
  class SyncStatusService
    HISTORY_KEY = "loft_sync_history".freeze

    def initialize(tenant: Current.tenant)
      @tenant = tenant
    end

    def mark_processing!(message:, mode: nil, progress: 0)
      setting_set("loft_sync_status", "processing", "Status da sincronização Loft")
      setting_set("loft_sync_progress", progress.to_i.clamp(0, 100).to_s, "Progresso da sincronização Loft")
      setting_set("loft_last_sync_message", message.to_s, "Resumo da última execução Loft")
      append_history!(status: "processing", message: message, mode: mode, stats: {})
    end

    def update_progress!(progress:, message: nil)
      setting_set("loft_sync_progress", progress.to_i.clamp(0, 100).to_s, "Progresso da sincronização Loft")
      setting_set("loft_last_sync_message", message.to_s, "Resumo da última execução Loft") if message.present?
    end

    def mark_completed!(message:, mode: nil, stats: {})
      stamp_last_sync_time!
      setting_set("loft_sync_status", "completed", "Status da sincronização Loft")
      setting_set("loft_sync_progress", "100", "Progresso da sincronização Loft")
      setting_set("loft_last_sync_message", message.to_s, "Resumo da última execução Loft")
      append_history!(status: "completed", message: message, mode: mode, stats: stats)
    end

    def mark_failed!(message:, mode: nil, stats: {})
      stamp_last_sync_time!
      setting_set("loft_sync_status", "failed", "Status da sincronização Loft")
      setting_set("loft_last_sync_message", message.to_s, "Resumo da última execução Loft")
      append_history!(status: "failed", message: message, mode: mode, stats: stats)
    end

    def mark_skipped!(message:, mode: nil)
      stamp_last_sync_time!
      setting_set("loft_sync_status", "skipped", "Status da sincronização Loft")
      setting_set("loft_last_sync_message", message.to_s, "Resumo da última execução Loft")
      append_history!(status: "skipped", message: message, mode: mode, stats: {})
    end

    def history(limit: 5)
      parse_history.first(limit)
    end

    private

    def append_history!(status:, message:, mode:, stats:)
      entries = parse_history
      entries.unshift(
        {
          "at" => Time.current.iso8601,
          "status" => status.to_s,
          "mode" => mode.to_s.presence,
          "message" => message.to_s,
          "stats" => (stats || {}).stringify_keys
        }
      )
      setting_set(HISTORY_KEY, entries.first(5).to_json, "Histórico das últimas sincronizações Loft")
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
      setting_set("loft_last_sync_at", Time.current.iso8601, "Última execução Loft")
    end

    def setting_get(key, default = nil)
      Setting.tenant_get(key, default, tenant: @tenant)
    end

    def setting_set(key, value, description)
      Setting.set(key, value, description, tenant: @tenant)
    end
  end
end

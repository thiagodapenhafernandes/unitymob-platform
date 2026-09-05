module Integrations
  class SyncStatus
    def initialize(tenant: Current.tenant)
      @tenant = tenant
    end

    def mark_processing!(message:, mode: nil, progress: 0)
      write_status("processing", message: message, mode: mode, progress: progress.to_i)
    end

    def update_progress!(progress:, message: nil)
      setting_set("sync_progress", progress.to_i.clamp(0, 100).to_s, self.class::PROGRESS_DESCRIPTION)
      setting_set("last_sync_message", message.to_s, "Resumo da última execução #{self.class::LABEL}") if message.present?
    end

    def mark_skipped!(message:, mode: nil)
      write_status("skipped", message: message, mode: mode)
    end

    def history(limit: 5)
      parse_history.first(limit)
    end

    private

    def write_status(status, message:, mode:, progress: nil, stats: {})
      setting_set("last_sync_at", Time.current.iso8601, "Última execução #{self.class::LABEL}") unless status == "processing"
      setting_set("sync_status", status, "Status da sincronização #{self.class::LABEL}")
      setting_set("sync_progress", progress.to_i.clamp(0, 100).to_s, self.class::PROGRESS_DESCRIPTION) unless progress.nil?
      setting_set("last_sync_message", message.to_s, "Resumo da última execução #{self.class::LABEL}")
      entry = { "at" => Time.current.iso8601, "status" => status, "mode" => mode.to_s.presence, "message" => message.to_s }
      entry["stats"] = (stats || {}).stringify_keys if self.class::INCLUDE_STATS
      setting_set("sync_history", [entry, *parse_history].first(5).to_json, "Histórico das últimas sincronizações #{self.class::LABEL}")
    end

    def parse_history
      parsed = JSON.parse(Setting.tenant_get(self.class::HISTORY_KEY, "[]", tenant: @tenant).to_s)
      parsed.is_a?(Array) ? parsed : []
    rescue JSON::ParserError
      []
    end

    def setting_set(suffix, value, description)
      Setting.set("#{self.class::PREFIX}_#{suffix}", value, description, tenant: @tenant)
    end
  end
end

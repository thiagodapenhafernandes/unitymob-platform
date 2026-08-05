module Vista
  # Progresso da sincronização Vista → AdminUser persistido em Settings para
  # sobreviver entre o worker (job) e os requests HTTP (polling do admin).
  #
  # Chaves:
  #   vista_agents_sync_status        — idle | processing | completed | failed
  #   vista_agents_sync_progress      — 0..100
  #   vista_agents_sync_message       — mensagem curta ("Página 3 de 8…")
  #   vista_agents_sync_stats         — JSON { processed, created, updated, errors, page, total_pages }
  #   vista_agents_sync_started_at    — ISO8601
  #   vista_agents_sync_finished_at   — ISO8601
  class SyncStatusService
    def initialize(namespace: "agents_sync", tenant: Current.tenant)
      @ns = namespace
      @tenant = tenant
    end

    def status_key;   "vista_#{@ns}_status";       end
    def progress_key; "vista_#{@ns}_progress";     end
    def message_key;  "vista_#{@ns}_message";      end
    def stats_key;    "vista_#{@ns}_stats";        end
    def started_key;  "vista_#{@ns}_started_at";   end
    def finished_key; "vista_#{@ns}_finished_at";  end

    def mark_processing!(message:, stats: {})
      setting_set(status_key, "processing")
      setting_set(progress_key, "0")
      setting_set(message_key, message.to_s)
      setting_set(stats_key, stats.to_json)
      setting_set(started_key, Time.current.iso8601)
      setting_set(finished_key, "")
    end

    def update_progress!(progress:, message: nil, stats: nil)
      setting_set(progress_key, progress.to_i.clamp(0, 100).to_s)
      setting_set(message_key, message.to_s) if message.present?
      setting_set(stats_key, stats.to_json) if stats.present?
    end

    def mark_completed!(message:, stats: {})
      setting_set(status_key, "completed")
      setting_set(progress_key, "100")
      setting_set(message_key, message.to_s)
      setting_set(stats_key, stats.to_json)
      setting_set(finished_key, Time.current.iso8601)
    end

    def mark_failed!(message:, stats: {})
      setting_set(status_key, "failed")
      setting_set(message_key, message.to_s)
      setting_set(stats_key, stats.to_json)
      setting_set(finished_key, Time.current.iso8601)
    end

    def snapshot
      raw_stats = setting_get(stats_key, "{}").to_s
      stats = JSON.parse(raw_stats) rescue {}
      {
        status:       setting_get(status_key, "idle"),
        progress:     setting_get(progress_key, "0").to_i,
        message:      setting_get(message_key, ""),
        stats:        stats,
        started_at:   parse_time(setting_get(started_key, "")),
        finished_at:  parse_time(setting_get(finished_key, ""))
      }
    end

    private

    def parse_time(str)
      return nil if str.to_s.empty?
      Time.iso8601(str) rescue nil
    end

    def setting_get(key, default = nil)
      Setting.tenant_get(key, default, tenant: @tenant)
    end

    def setting_set(key, value)
      Setting.set(key, value, nil, tenant: @tenant)
    end
  end
end

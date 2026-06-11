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
    def initialize(namespace: "agents_sync")
      @ns = namespace
    end

    def status_key;   "vista_#{@ns}_status";       end
    def progress_key; "vista_#{@ns}_progress";     end
    def message_key;  "vista_#{@ns}_message";      end
    def stats_key;    "vista_#{@ns}_stats";        end
    def started_key;  "vista_#{@ns}_started_at";   end
    def finished_key; "vista_#{@ns}_finished_at";  end

    def mark_processing!(message:, stats: {})
      Setting.set(status_key, "processing")
      Setting.set(progress_key, "0")
      Setting.set(message_key, message.to_s)
      Setting.set(stats_key, stats.to_json)
      Setting.set(started_key, Time.current.iso8601)
      Setting.set(finished_key, "")
    end

    def update_progress!(progress:, message: nil, stats: nil)
      Setting.set(progress_key, progress.to_i.clamp(0, 100).to_s)
      Setting.set(message_key, message.to_s) if message.present?
      Setting.set(stats_key, stats.to_json) if stats.present?
    end

    def mark_completed!(message:, stats: {})
      Setting.set(status_key, "completed")
      Setting.set(progress_key, "100")
      Setting.set(message_key, message.to_s)
      Setting.set(stats_key, stats.to_json)
      Setting.set(finished_key, Time.current.iso8601)
    end

    def mark_failed!(message:, stats: {})
      Setting.set(status_key, "failed")
      Setting.set(message_key, message.to_s)
      Setting.set(stats_key, stats.to_json)
      Setting.set(finished_key, Time.current.iso8601)
    end

    def snapshot
      raw_stats = Setting.get(stats_key, "{}").to_s
      stats = JSON.parse(raw_stats) rescue {}
      {
        status:       Setting.get(status_key, "idle"),
        progress:     Setting.get(progress_key, "0").to_i,
        message:      Setting.get(message_key, ""),
        stats:        stats,
        started_at:   parse_time(Setting.get(started_key, "")),
        finished_at:  parse_time(Setting.get(finished_key, ""))
      }
    end

    private

    def parse_time(str)
      return nil if str.to_s.empty?
      Time.iso8601(str) rescue nil
    end
  end
end

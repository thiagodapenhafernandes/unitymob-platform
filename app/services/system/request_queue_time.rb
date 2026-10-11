# frozen_string_literal: true

module System
  # Tempo (ms) que o request esperou antes do Rails atendê-lo, a partir do
  # header X-Request-Start. Exige que o proxy envie o header, ex. (nginx):
  # proxy_set_header X-Request-Start "t=${msec}";
  # Sem header (ou com valor inválido), retorna nil e nada é logado.
  module RequestQueueTime
    MAX_QUEUE_MS = 3_600_000

    def self.ms(request, now: Time.current)
      raw = request.get_header("HTTP_X_REQUEST_START").to_s.sub(/\At=/, "")
      return if raw.blank?

      started_at = parse(raw)
      return if started_at.nil?

      delta_ms = ((now.to_f - started_at) * 1000).round(1)
      delta_ms if delta_ms >= 0 && delta_ms < MAX_QUEUE_MS
    end

    def self.parse(raw)
      return raw.to_f if raw.match?(/\A\d+\.\d+\z/)
      return raw.to_f / 1000 if raw.match?(/\A\d{13}\z/)
      return raw.to_f if raw.match?(/\A\d{10}\z/)

      nil
    end
    private_class_method :parse
  end
end

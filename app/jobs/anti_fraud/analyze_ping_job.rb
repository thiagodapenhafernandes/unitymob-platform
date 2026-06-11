module AntiFraud
  # Roda assíncrono após cada ping. Se detecta sinal de fraude, flagga o
  # ping + o check_in e registra no audit log.
  class AnalyzePingJob < ApplicationJob
    queue_as :checkin

    def perform(ping_id)
      ping = LocationPing.find_by(id: ping_id)
      return unless ping

      result = AntiFraud::CheckIns::Analyzer.analyze_ping(ping)
      return unless result[:suspicious]

      ping.update!(suspicious: true, suspicious_reasons: result[:reasons])

      check_in = ping.check_in
      check_in.flag_suspicious!(reasons: result[:reasons])

      CheckinAuditLog.log!(
        action: "flagged_suspicious",
        check_in: check_in,
        metadata: { reasons: result[:reasons], ping_id: ping.id }
      )
    end
  end
end

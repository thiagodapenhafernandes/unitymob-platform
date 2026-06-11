# frozen_string_literal: true

module CheckIns
  # Fecha um check-in ativo com status informado.
  # Tipos de checkout suportados:
  #   :closed_manual              — corretor clicou em check-out
  #   :closed_auto_shift_end      — job cron detectou fim de turno
  #   :closed_auto_out_of_radius  — ping detectou saída do raio
  #   :closed_admin_force         — admin forçou manualmente
  class CheckOutService
    def initialize(check_in:, reason: :closed_manual, lat: nil, lng: nil, ip: nil, accuracy: nil, actor: nil)
      @check_in = check_in
      @reason = reason
      @lat = lat
      @lng = lng
      @ip = ip
      @accuracy = accuracy
      @actor = actor
    end

    def call
      return { success: false, error: :not_active, message: "Check-in não está ativo." } unless @check_in&.active?

      @check_in.force_close!(
        reason: @reason,
        lat: @lat,
        lng: @lng,
        ip: @ip,
        accuracy: @accuracy
      )

      CheckinAuditLog.log!(
        action: @reason == :closed_admin_force ? "forced_closed" : "closed",
        check_in: @check_in,
        actor: @actor,
        ip: @ip,
        metadata: {
          reason: @reason.to_s,
          duration_seconds: @check_in.duration.to_i
        }
      )

      { success: true, check_in: @check_in.reload }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: :save_failed, message: e.record.errors.full_messages.to_sentence }
    end
  end
end

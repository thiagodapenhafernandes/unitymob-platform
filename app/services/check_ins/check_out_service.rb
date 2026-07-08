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
      return not_active_result unless @check_in&.active?

      # Transição active→closed é serializada sob lock pessimista para evitar
      # TOCTOU (double-tap no PWA, retry de rede, ping vs. jobs cron rodando
      # no mesmo instante). Recarrega e revalida ativo sob o lock: se outro
      # fechador já venceu, o segundo vira no-op idempotente (:not_active),
      # sem sobrescrever checked_out_at/status/checkout_ip nem duplicar audit.
      @check_in.with_lock do
        return not_active_result unless @check_in.active?

        @check_in.force_close!(
          reason: @reason,
          lat: @lat,
          lng: @lng,
          ip: @ip,
          accuracy: @accuracy
        )

        # Captura as coordenadas do checkout ANTES do reload — o reload dispara
        # after_find e re-extrai via SQL; guardamos os valores usados aqui para
        # que o caller receba as coords mesmo sem depender do after_find.
        checkout_coords = {
          checkout_latitude:  @lat,
          checkout_longitude: @lng
        }

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
        remove_from_distribution_queues_if_configured!

        @check_in.reload
        @check_in.checkout_latitude  ||= checkout_coords[:checkout_latitude]
        @check_in.checkout_longitude ||= checkout_coords[:checkout_longitude]

        { success: true, check_in: @check_in }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: :save_failed, message: e.record.errors.full_messages.to_sentence }
    end

    private

    def not_active_result
      { success: false, error: :not_active, message: "Check-in não está ativo." }
    end

    def remove_from_distribution_queues_if_configured!
      store = @check_in.store
      shift_key = @check_in.respond_to?(:turno) ? @check_in.turno.presence : nil
      return if store.blank? || shift_key.blank?
      return unless store.remove_from_queue_after_checkout?(shift_key)

      rules = @check_in.tenant.distribution_rules
                       .where(active: true)
                       .where("? = ANY(checkin_store_ids)", store.id)
      removed = DistributionRuleAgent
        .where(distribution_rule_id: rules.select(:id), admin_user_id: @check_in.admin_user_id)
        .delete_all

      return unless removed.positive?

      CheckinAuditLog.log!(
        action: "distribution_queue_removed",
        check_in: @check_in,
        actor: @actor,
        ip: @ip,
        metadata: { removed_agents: removed, shift: shift_key, store_id: store.id }
      )
    rescue StandardError => e
      Rails.logger.warn("[CheckIns::CheckOutService] queue removal skipped: #{e.class}: #{e.message}")
    end
  end
end

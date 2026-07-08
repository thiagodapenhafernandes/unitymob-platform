# frozen_string_literal: true

module CheckIns
  # Roda a cada 5 minutos. Pega check-ins ativos cuja ÚLTIMA atividade
  # (último ping ou início) passou de STALE_THRESHOLD e fecha como
  # :closed_auto_no_signal — o corretor ficou SEM SINAL (app em background /
  # tela apagada). Ausência de ping NÃO é prova de que saiu do raio, por isso
  # o motivo é "sem sinal" e não :closed_auto_out_of_radius (que é reservado
  # para quando um ping realmente detecta saída do geofence).
  class StaleActiveCheckinJob < ApplicationJob
    queue_as :checkin

    STALE_THRESHOLD = 10.minutes

    def perform(tenant_id: nil)
      threshold = STALE_THRESHOLD.ago
      closed = 0

      tenants_for(tenant_id).find_each do |tenant|
        Current.set(tenant: tenant) do
          # Flag POR-TENANT: avaliar já com o tenant no contexto, senão
          # Current.tenant=nil lê a global inexistente e aborta a varredura.
          next unless FieldFeatureGate.field_checkin_enabled?

          active_scope = tenant.check_ins.where(status: :active)

          active_scope.find_in_batches(batch_size: 1000) do |batch|
            # Um único SELECT ... GROUP BY para o último ping de todos os
            # check-ins do lote, evitando um SELECT por linha (N+1).
            ids = batch.map(&:id)
            last_ping_by_check_in = LocationPing
                                    .where(check_in_id: ids)
                                    .group(:check_in_id)
                                    .maximum(:recorded_at)

            batch.each do |check_in|
              last_ping = last_ping_by_check_in[check_in.id]
              last_activity = [last_ping, check_in.checked_in_at].compact.max
              next if last_activity.nil? || last_activity >= threshold

              CheckIns::CheckOutService.new(
                check_in: check_in,
                reason: :closed_auto_no_signal
              ).call
              closed += 1
            end
          end
        end
      end

      Rails.logger.info("[StaleActiveCheckinJob] closed=#{closed}") if closed.positive?
      closed
    end

    private

    def tenants_for(tenant_id)
      tenant_id.present? ? Tenant.where(id: tenant_id) : Tenant.active
    end
  end
end

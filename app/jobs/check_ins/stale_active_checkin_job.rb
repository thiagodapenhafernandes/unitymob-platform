# frozen_string_literal: true

module CheckIns
  # Roda a cada 5 minutos. Pega check-ins ativos cuja ÚLTIMA atualização
  # (último ping ou início) passou de STALE_THRESHOLD. Fecha como
  # :closed_auto_out_of_radius assumindo que o corretor sumiu.
  class StaleActiveCheckinJob < ApplicationJob
    queue_as :checkin

    STALE_THRESHOLD = 10.minutes

    def perform(tenant_id: nil)
      return unless FieldFeatureGate.field_checkin_enabled?

      threshold = STALE_THRESHOLD.ago
      closed = 0

      tenants_for(tenant_id).find_each do |tenant|
        Current.set(tenant: tenant) do
          tenant.check_ins.where(status: :active).find_each do |check_in|
            last_ping = check_in.location_pings.maximum(:recorded_at)
            last_activity = [last_ping, check_in.checked_in_at].compact.max
            next unless last_activity < threshold

            CheckIns::CheckOutService.new(
              check_in: check_in,
              reason: :closed_auto_out_of_radius
            ).call
            closed += 1
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

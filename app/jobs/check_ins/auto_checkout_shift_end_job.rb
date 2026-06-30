# frozen_string_literal: true

module CheckIns
  # Roda a cada minuto (config/recurring.yml). Varre check-ins ativos cujo
  # turno terminou há mais que store.auto_checkout_after_minutes e fecha
  # com status :closed_auto_shift_end.
  class AutoCheckoutShiftEndJob < ApplicationJob
    queue_as :checkin

    def perform(tenant_id: nil)
      return unless FieldFeatureGate.field_checkin_enabled?

      now = Time.current
      closed = 0

      tenants_for(tenant_id).find_each do |tenant|
        Current.set(tenant: tenant) do
          tenant.check_ins.where(status: :active)
                .includes(:store, :store_shift)
                .find_each do |check_in|
            next if check_in.store_shift.nil?

            store = check_in.store
            shift = check_in.store_shift
            local_now = now.in_time_zone(store.timezone_obj)

            # Só considera turnos cujo end_time já passou hoje
            shift_end_today = Time.use_zone(store.timezone) do
              Time.zone.local(local_now.year, local_now.month, local_now.day,
                              shift.end_time.hour, shift.end_time.min)
            end

            grace = store.auto_checkout_after_minutes.to_i.minutes
            next unless now >= shift_end_today + grace

            CheckIns::CheckOutService.new(
              check_in: check_in,
              reason: :closed_auto_shift_end
            ).call
            closed += 1
          end
        end
      end

      Rails.logger.info("[AutoCheckoutShiftEndJob] closed=#{closed}") if closed.positive?
      closed
    end

    private

    def tenants_for(tenant_id)
      tenant_id.present? ? Tenant.where(id: tenant_id) : Tenant.active
    end
  end
end

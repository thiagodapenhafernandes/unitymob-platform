# frozen_string_literal: true

module CheckIns
  # Roda a cada minuto (config/recurring.yml). Varre check-ins ativos cujo
  # turno terminou há mais que store.auto_checkout_after_minutes e fecha
  # com status :closed_auto_shift_end.
  class AutoCheckoutShiftEndJob < ApplicationJob
    queue_as :checkin

    def perform(tenant_id: nil)
      now = Time.current
      closed = 0

      tenants_for(tenant_id).find_each do |tenant|
        Current.set(tenant: tenant) do
          # A flag é POR-TENANT: precisa ser avaliada COM o tenant no contexto,
          # senão Current.tenant=nil lê a global inexistente e aborta tudo.
          next unless FieldFeatureGate.field_checkin_enabled?

          tenant.check_ins.where(status: :active)
                .includes(:store, :store_shift)
                .find_each do |check_in|
            store = check_in.store
            shift = check_in.store_shift

            shift_end = operational_shift_end_for(check_in, store) || shift_end_for(check_in, store, shift)
            next if shift_end.nil?

            grace = operational_shift_key(check_in).present? ? store.auto_checkout_delay_for(operational_shift_key(check_in)) : store.auto_checkout_after_minutes.to_i.minutes
            next unless now >= shift_end + grace

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

    def operational_shift_key(check_in)
      check_in.respond_to?(:turno) ? check_in.turno.presence : nil
    end

    def operational_shift_end_for(check_in, store)
      shift_key = operational_shift_key(check_in)
      return nil if shift_key.blank?

      shift_end = store.operational_shift_end_time(shift_key, check_in.checked_in_at)
      return nil if shift_end.nil?
      return shift_end if check_in.checked_in_at.nil? || shift_end >= check_in.checked_in_at.in_time_zone(store.timezone_obj)

      shift_end + 1.day
    end

    # Instante ABSOLUTO em que o turno deste check-in termina, ancorado na DATA
    # do próprio check-in (no fuso da loja) — não em "hoje". Isso corrige dois
    # bugs: (1) turno que começou ontem e cruzou a meia-noite nunca fechava
    # porque a âncora era o dia de hoje; (2) usar o horário de HOJE para um
    # check-in de dia anterior inflava a duração ao fechar.
    #
    # Suporta turnos que atravessam 00:00 (end_time <= start_time): nesse caso o
    # fim do turno cai no dia seguinte ao início. Fallback de segurança: se o
    # fim calculado ainda ficar antes do checked_in_at, soma 1 dia.
    def shift_end_for(check_in, store, shift)
      return nil if shift.nil?

      tz = store.timezone_obj
      checked_in_local = check_in.checked_in_at&.in_time_zone(tz)
      return nil if checked_in_local.nil?

      Time.use_zone(tz) do
        anchor = checked_in_local.to_date
        # end_time é coluna TIME: ler .hour/.min sofre conversão de fuso sobre a
        # data-dummy 2000 (DST) e desloca ~2h. strftime dá a hora de parede real.
        end_h = shift.end_time.strftime("%H").to_i
        end_m = shift.end_time.strftime("%M").to_i
        shift_end = Time.zone.local(anchor.year, anchor.month, anchor.day, end_h, end_m)

        # Turno overnight (fim <= início) ou fim já anterior ao check-in:
        # o término real é no dia seguinte.
        overnight = shift.end_time.strftime("%H:%M:%S") <= shift.start_time.strftime("%H:%M:%S")
        shift_end += 1.day if overnight || shift_end < checked_in_local

        shift_end
      end
    end

    def tenants_for(tenant_id)
      tenant_id.present? ? Tenant.where(id: tenant_id) : Tenant.active
    end
  end
end

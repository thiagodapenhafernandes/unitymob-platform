require "fugit"

module Loft
  class ScheduledSyncService
    LAST_SLOT_KEY = "loft_schedule_last_slot".freeze

    def call(now: Time.current)
      return 0 unless Setting.get("loft_schedule_enabled", "false") == "true"

      cron = ::Fugit::Cron.parse(Setting.get("loft_schedule_cron", ""))
      return 0 unless cron&.match?(now)

      slot = now.to_i / 60
      return 0 if Setting.get(LAST_SLOT_KEY).to_s == slot.to_s

      count = 0
      Tenant.active.find_each do |tenant|
        LoftSyncJob.perform_later(tenant_id: tenant.id)
        count += 1
      end
      Setting.set(LAST_SLOT_KEY, slot.to_s, "Último minuto agendado da sincronização Loft")
      count
    end
  end
end

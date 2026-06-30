require "fugit"

module Loft
  class ScheduledSyncService
    DEFAULT_CRON = "20 4 * * *".freeze
    LAST_SLOT_KEY = "loft_schedule_last_slot".freeze

    def call(now: Time.current)
      return { status: :disabled, message: "Agendamento Loft desativado." } unless enabled?

      cron_expression = Setting.get("loft_schedule_cron", DEFAULT_CRON).to_s
      cron = Fugit::Cron.parse(cron_expression)
      return { status: :invalid, message: "Cron inválido: #{cron_expression}" } if cron.nil?
      return { status: :not_due, message: "Janela ainda não atingida." } unless cron.match?(now)

      slot = now.utc.strftime("%Y-%m-%d %H:%M")
      last_slot = Setting.get(LAST_SLOT_KEY).to_s
      return { status: :already_ran, message: "Slot #{slot} já executado." } if slot == last_slot

      mode = Setting.get("loft_schedule_mode", "full").to_s
      mode = "full" unless %w[full batch].include?(mode)
      batch_size = Setting.get("loft_sync_batch_size", "100").to_i

      tenants = Tenant.active.to_a
      tenants.each do |tenant|
        LoftSyncJob.perform_later(mode: mode, batch_size: batch_size, tenant_id: tenant.id)
      end
      Setting.set(LAST_SLOT_KEY, slot, "Último slot executado no scheduler Loft")

      { status: :enqueued, message: "Loft sync agendado no slot #{slot} para #{tenants.size} tenant(s)." }
    rescue => e
      { status: :error, message: e.message }
    end

    private

    def enabled?
      Setting.get("loft_schedule_enabled", "false") == "true"
    end
  end
end

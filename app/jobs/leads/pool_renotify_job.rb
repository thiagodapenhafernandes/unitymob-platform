module Leads
  class PoolRenotifyJob < ApplicationJob
    queue_as :default

    POOL_ACTIVITY_KINDS = %w[shark_tank_ready pocket_pool_ready pool_renotified].freeze

    # Mantém compatibilidade com jobs individuais já presentes na fila.
    # Novas rodadas são encontradas pelo agendamento recorrente, sem cadeias.
    def perform(lead_id = nil, tenant_id: nil)
      if lead_id
        tenant = tenant_id.present? ? Tenant.find_by(id: tenant_id) : Current.tenant
        raise ArgumentError, "Tenant obrigatório para renotificar Bolsão" unless tenant

        Current.set(tenant: tenant) { renotify(tenant.leads.find_by(id: lead_id)) }
      else
        Tenant.find_each do |tenant|
          Current.set(tenant: tenant) do
            next unless LeadSetting.instance(tenant: tenant).notify_on_shark_tank?

            tenant.leads.waiting_acceptance.where(admin_user_id: nil)
                  .joins(:distribution_rule)
                  .where(distribution_rules: { tenant_id: tenant.id, active: true, pool_renotify_mode: "interval" })
                  .find_each do |lead|
              renotify(lead)
            rescue => e
              Rails.logger.warn("[PoolRenotifyJob] lead_id=#{lead.id} error=#{e.class}")
            end
          end
        rescue => e
          Rails.logger.warn("[PoolRenotifyJob] tenant_id=#{tenant.id} error=#{e.class}")
        end
      end
    end

    private

    def renotify(lead)
      return unless lead

      lead.with_lock do
        rule = lead.distribution_rule
        next unless lead.admin_user_id.nil? && Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance)
        next unless rule&.tenant_id == lead.tenant_id && rule.active? && rule.pool_mode? && rule.pool_renotify_interval?
        next unless LeadSetting.instance(tenant: lead.tenant).notify_on_shark_tank?

        last_round_at = lead.activities.where(kind: POOL_ACTIVITY_KINDS).maximum(:created_at) || lead.created_at
        now = Time.current
        next if last_round_at + rule.pool_renotify_minutes_value.minutes > now

        candidates = rule.candidates_filtered_by_checkin
        next if candidates.empty?

        Leads::NotificationDispatcher.notify_pool(lead, rule, candidates: candidates, context: "pool_renotify")
        lead.activities.create!(
          kind: "pool_renotified",
          created_at: now,
          metadata: {
            rule_id: rule.id,
            rule_name: rule.name,
            interval_minutes: rule.pool_renotify_minutes_value
          }
        )
      end
    end
  end
end

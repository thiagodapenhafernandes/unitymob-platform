module Leads
  class PocketSweepJob < ApplicationJob
    queue_as :default
    BATCH_LIMIT = 200

    def perform
      # Varre por tenant (aproveita o índice composto (tenant_id, status)) em
      # vez de consultar a base inteira cross-tenant a cada minuto.
      Tenant.find_each do |tenant|
        Current.set(tenant: tenant) do
          tenant.leads.waiting_acceptance
                .where.not(admin_user_id: nil, distribution_rule_id: nil)
                .includes(:distribution_rule)
                .limit(BATCH_LIMIT)
                .find_each do |lead|
            Leads::PocketExpirationService.expire!(lead, source: "sweep")
          rescue => e
            Rails.logger.warn("[PocketSweepJob] falha ao verificar lead #{lead.id}: #{e.class} #{e.message}")
          end
        end
      rescue => e
        Rails.logger.warn("[PocketSweepJob] falha ao varrer tenant #{tenant.id}: #{e.class} #{e.message}")
      end
    end
  end
end

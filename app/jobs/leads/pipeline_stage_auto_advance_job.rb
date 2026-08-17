module Leads
  class PipelineStageAutoAdvanceJob < ApplicationJob
    queue_as :default

    def perform
      LeadSetting.includes(:tenant).find_each do |setting|
        next unless setting.stage_automation_sweep_due?

        Current.set(tenant: setting.tenant) do
          Leads::PipelineStageAutoAdvanceService.call(tenant: setting.tenant)
          setting.update_column(:stage_automation_last_swept_at, Time.current)
        end
      rescue => e
        Rails.logger.warn("[lead stage auto advance job] tenant=#{setting.tenant_id} #{e.class}: #{e.message}")
      end
    end
  end
end

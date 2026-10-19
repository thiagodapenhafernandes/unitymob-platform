class Ga4ConversionRecoveryJob < ApplicationJob
  queue_as :default

  def perform
    Ga4ConversionConfig.where(enabled: true).find_each do |config|
      scope = Ga4ConversionEvent.where(tenant_id: config.tenant_id)
      scope.where(status: "sending").where("attempted_at < ?", 15.minutes.ago).update_all(status: "uncertain", updated_at: Time.current)
      scope.where(status: "pending").where("created_at < ?", 1.minute.ago).find_each do |event|
        Ga4ConversionDeliveryJob.perform_later(config.tenant_id, event.id)
      end
    end
  end
end

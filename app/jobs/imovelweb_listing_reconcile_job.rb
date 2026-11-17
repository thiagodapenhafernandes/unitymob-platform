class ImovelwebListingReconcileJob < ApplicationJob
  queue_as :sync

  def perform
    ImovelwebConnection.where(environment: "production", enabled: true).where.not(authorized_at: nil).includes(:tenant).find_each do |connection|
      ImovelwebListingSyncJob.perform_later(connection.id) if connection.receiving?
    end
  end
end

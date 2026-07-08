class DwvIncrementalSyncJob < ApplicationJob
  queue_as :dwv
  queue_with_priority(-10)

  def perform(limit: nil, max_pages: nil, last_updates: nil)
    DwvSyncAllTenantsJob.perform_now(
      mode: "incremental",
      limit: limit,
      max_pages: max_pages,
      last_updates: last_updates
    )
  end
end

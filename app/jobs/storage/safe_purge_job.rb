module Storage
  class SafePurgeJob < ApplicationJob
    queue_as :default

    def perform(blob_id)
      Storage::ActiveStorageRegistry.register_if_available! if defined?(Storage::ActiveStorageRegistry)

      blob = ActiveStorage::Blob.find_by(id: blob_id)
      return if blob.blank?
      return if blob.attachments.exists?

      Storage::BlobAuditRecorder.record!(
        blob: blob,
        action: "purge_started",
        source: "safe_purge_job"
      )
      blob.purge
    rescue ActiveStorage::FileNotFoundError
      Storage::BlobAuditRecorder.record!(
        blob: blob,
        action: "purge_missing_deleted",
        source: "safe_purge_job"
      ) if blob.present?
      blob&.destroy
    end
  end
end

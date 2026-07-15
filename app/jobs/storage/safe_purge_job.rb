module Storage
  class SafePurgeJob < ApplicationJob
    queue_as :default

    def perform(blob_id)
      Storage::ActiveStorageRegistry.register_if_available! if defined?(Storage::ActiveStorageRegistry)

      blob = ActiveStorage::Blob.find_by(id: blob_id)
      return if blob.blank?
      return if blob.attachments.exists?

      blob.purge
    rescue ActiveStorage::FileNotFoundError
      blob&.delete
    end
  end
end

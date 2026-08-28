module Storage
  class SafePurgeJob < ApplicationJob
    queue_as :default

    def perform(blob_id)
      Storage::ActiveStorageRegistry.register_if_available! if defined?(Storage::ActiveStorageRegistry)

      blob = ActiveStorage::Blob.find_by(id: blob_id)
      return if blob.blank?
      if blob.attachments.exists?
        record_blocked_attached_blob(blob)
        return
      end

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

    private

    def record_blocked_attached_blob(blob)
      protected_attachments = Storage::ProtectedBlobPolicy.protected_attachments_for(blob)
      action = protected_attachments.any? ? "purge_blocked_protected_blob" : "purge_blocked_attached_blob"

      Storage::BlobAuditRecorder.record!(
        blob: blob,
        action: action,
        source: "safe_purge_job",
        attachment: protected_attachments.first || blob.attachments.first,
        metadata: {
          attachment_count: blob.attachments.count,
          protected_attachments: protected_attachments.map { |attachment| attachment_context(attachment) }
        }
      )
    end

    def attachment_context(attachment)
      {
        id: attachment.id,
        name: attachment.name,
        record_type: attachment.record_type,
        record_id: attachment.record_id
      }
    end
  end
end

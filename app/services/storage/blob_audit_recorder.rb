module Storage
  class BlobAuditRecorder
    def self.record!(...)
      new(...).record!
    end

    def initialize(blob:, action:, source:, attachment: nil, metadata: {})
      @blob = blob
      @action = action.to_s
      @source = source.to_s
      @attachment = attachment
      @metadata = metadata.to_h
    end

    def record!
      return if blob.blank?
      return unless defined?(ActiveStorageBlobAuditLog)

      ActiveStorageBlobAuditLog.create!(
        tenant_id: tenant_id,
        admin_user_id: Current.admin_user&.id,
        blob_id: blob.id,
        attachment_id: attachment&.id,
        record_type: attachment&.record_type,
        record_id: attachment&.record_id,
        attachment_name: attachment&.name,
        action: action,
        source: source,
        key: blob.key,
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size,
        checksum: blob.checksum,
        service_name: blob.service_name,
        metadata: metadata,
        ip: Current.request_ip,
        user_agent: Current.request_user_agent
      )
    rescue StandardError => e
      Rails.logger.warn("[storage_blob_audit] action=#{action} source=#{source} blob_id=#{blob&.id} error=#{e.class}: #{e.message}")
      nil
    end

    private

    attr_reader :blob, :action, :source, :attachment, :metadata

    def tenant_id
      Current.tenant&.id ||
        tenant_id_from_attachment_record ||
        tenant_id_from_blob_metadata
    end

    def tenant_id_from_attachment_record
      record = attachment&.record
      return unless record&.respond_to?(:tenant_id)

      record.tenant_id
    end

    def tenant_id_from_blob_metadata
      blob.metadata.to_h["tenant_id"].presence
    end
  end
end

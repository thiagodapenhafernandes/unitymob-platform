module Storage
  class CriticalBlobIntegrityJob < ApplicationJob
    queue_as :checkin

    class MissingCriticalBlob < StandardError; end
    class CriticalBlobCheckFailed < StandardError; end

    def perform
      Storage::ActiveStorageRegistry.register_if_available! if defined?(Storage::ActiveStorageRegistry)

      checked = 0
      missing = 0
      failed = 0

      Storage::ProtectedBlobPolicy.critical_attachment_scope.find_each do |attachment|
        blob = attachment.blob
        next if blob.blank?

        with_tenant_context(attachment, blob) do
          checked += 1
          if blob_exists?(blob)
            next
          end

          missing += 1
          record_missing_blob(attachment, blob)
        end
      rescue StandardError => error
        failed += 1
        record_check_failure(attachment, error)
      end

      Rails.logger.info("[critical_blob_integrity] checked=#{checked} missing=#{missing} failed=#{failed}")
      { checked: checked, missing: missing, failed: failed }
    end

    private

    def blob_exists?(blob)
      Storage::ActiveStorageRegistry.fetch!(blob.service_name).exist?(blob.key)
    end

    def with_tenant_context(attachment, blob, &block)
      tenant = tenant_for(attachment, blob)
      return yield if tenant.blank?

      Current.set(tenant: tenant, &block)
    end

    def tenant_for(attachment, blob)
      record = attachment&.record
      return record.tenant if record.respond_to?(:tenant) && record.tenant.present?

      tenant_id = tenant_id_for(record, blob)
      Tenant.find_by(id: tenant_id) if tenant_id.present?
    end

    def record_missing_blob(attachment, blob)
      context = context_for(attachment, blob)

      Storage::BlobAuditRecorder.record!(
        blob: blob,
        attachment: attachment,
        action: "critical_blob_missing",
        source: "critical_blob_integrity_job",
        metadata: context
      )

      ErrorEvent.record!(
        MissingCriticalBlob.new("Blob crítico ausente no storage: #{attachment.record_type}##{attachment.record_id} #{attachment.name}"),
        source: "job",
        severity: "error",
        context: context.merge(report_source: "storage.critical_blob_integrity")
      ) if defined?(ErrorEvent)
    end

    def record_check_failure(attachment, error)
      blob = attachment&.blob
      context = context_for(attachment, blob).merge(
        error_class: error.class.name,
        error_message: error.message.to_s.truncate(300)
      )

      Storage::BlobAuditRecorder.record!(
        blob: blob,
        attachment: attachment,
        action: "critical_blob_check_failed",
        source: "critical_blob_integrity_job",
        metadata: context
      ) if blob.present?

      ErrorEvent.record!(
        CriticalBlobCheckFailed.new("Falha ao verificar blob crítico: #{attachment&.record_type}##{attachment&.record_id} #{attachment&.name}"),
        source: "job",
        severity: "warning",
        context: context.merge(report_source: "storage.critical_blob_integrity")
      ) if defined?(ErrorEvent)
    end

    def context_for(attachment, blob)
      record = attachment&.record
      {
        tenant_id: tenant_id_for(record, blob),
        blob_id: blob&.id,
        key: blob&.key,
        filename: blob&.filename&.to_s,
        content_type: blob&.content_type,
        byte_size: blob&.byte_size,
        checksum: blob&.checksum,
        service_name: blob&.service_name,
        attachment_id: attachment&.id,
        attachment_name: attachment&.name,
        record_type: attachment&.record_type,
        record_id: attachment&.record_id
      }.compact
    end

    def tenant_id_for(record, blob)
      return record.tenant_id if record&.respond_to?(:tenant_id)

      blob&.metadata.to_h["tenant_id"].presence
    rescue StandardError
      blob&.metadata.to_h["tenant_id"].presence
    end
  end
end

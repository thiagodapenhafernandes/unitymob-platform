module Habitations
  # Transient UI progress shared by web and media workers on the application host.
  # Database attachment/status remains authoritative for success and failure.
  module PhotoProcessingProgress
    module_function

    def write(attachment, phase)
      cache.write(key(attachment), phase, expires_in: 1.hour)
    rescue SystemCallError
      nil # Progress reporting must never fail the upload itself.
    end

    def read(attachment)
      cache.read(key(attachment)) || "received"
    rescue SystemCallError
      "received"
    end

    def key(attachment)
      "photo-progress/#{attachment.record.tenant_id}/#{attachment.id}/#{attachment.blob_id}"
    end

    def cache
      ActiveSupport::Cache::FileStore.new(Rails.root.join("tmp/photo-processing-progress"))
    end
  end
end

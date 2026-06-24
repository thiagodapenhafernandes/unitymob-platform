module Storage
  class BlobFactory
    def self.create_from_upload!(upload, service_name:, key_prefix: nil, metadata: {})
      service_name = service_name.to_sym
      Storage::ActiveStorageRegistry.fetch!(service_name) unless service_name == :local

      content_type = upload_content_type(upload)
      upload.rewind if upload.respond_to?(:rewind)

      ActiveStorage::Blob.create_and_upload!(
        key: storage_key(key_prefix, upload),
        io: upload,
        filename: upload_filename(upload),
        content_type: content_type,
        identify: false,
        metadata: metadata,
        service_name: service_name
      )
    end

    def self.storage_key(key_prefix, upload)
      return if key_prefix.blank?

      filename = upload_filename(upload).to_s
      [key_prefix, "#{SecureRandom.base58(24)}-#{filename.parameterize.presence || 'arquivo'}"].join("/")
    end

    def self.upload_filename(upload)
      if upload.respond_to?(:original_filename)
        upload.original_filename
      elsif upload.respond_to?(:filename)
        upload.filename
      else
        "arquivo"
      end
    end

    def self.upload_content_type(upload)
      content_type = upload.content_type if upload.respond_to?(:content_type)
      return content_type if content_type.present?

      Marcel::MimeType.for(upload, name: upload_filename(upload))
    ensure
      upload.rewind if upload.respond_to?(:rewind)
    end
  end
end

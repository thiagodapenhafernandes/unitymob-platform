require "mini_magick"

module Blog
  module Storage
    IMAGE_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
    CONTENT_TYPES = (IMAGE_TYPES + %w[application/pdf]).freeze
    MAX_BYTES = 20.megabytes
    module_function

    def service_name(tenant)
      return :test if Rails.env.test?
      return :development_sandbox if Rails.env.development?

      setting = StorageIntegrationSetting.current(tenant: tenant)
      raise ArgumentError, "Configure o DigitalOcean Spaces desta conta antes de enviar anexos." unless setting.digital_ocean_ready?

      name = setting.service_name_for_provider("digital_ocean")
      ::Storage::ActiveStorageRegistry.fetch!(name)
      name
    end

    def upload!(file, tenant:, images_only: false)
      raise ArgumentError, "Arquivo deve ser uma imagem ou PDF de até 20 MB." unless file.size.positive? && file.size <= MAX_BYTES
      type = Marcel::MimeType.for(file.tempfile, name: file.original_filename)
      raise ArgumentError, "Formato não permitido. Use JPEG, PNG, WebP, GIF ou PDF." unless (images_only ? IMAGE_TYPES : CONTENT_TYPES).include?(type)

      ActiveStorage::Blob.create_and_upload!(
        io: file.tempfile, filename: file.original_filename, content_type: type,
        service_name: service_name(tenant), metadata: { tenant_id: tenant.id, purpose: "blog" }.merge(image_metadata(file.tempfile.path, type))
      )
    end

    def image_metadata(path, content_type)
      return {} unless IMAGE_TYPES.include?(content_type)

      width, height = MiniMagick::Image.open(path.to_s).dimensions
      { width: width, height: height }
    rescue MiniMagick::Error
      raise ArgumentError, "A imagem está inválida ou corrompida."
    end

    def owned?(blob, tenant_id)
      blob.is_a?(ActiveStorage::Blob) && blob.metadata["tenant_id"].to_i == tenant_id &&
        blob.metadata["purpose"] == "blog" && CONTENT_TYPES.include?(blob.content_type) &&
        blob.byte_size <= MAX_BYTES && spaces_service?(blob.service_name)
    end

    def spaces_service?(name)
      return name == "test" if Rails.env.test?
      return name == "development_sandbox" if Rails.env.development?

      name.match?(/\A(?:do_spaces|do_spaces_db(?:_tenant_\d+)?)\z/)
    end
  end
end

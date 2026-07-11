module Storage
  class TransformVariantJob < ApplicationJob
    queue_as :media

    discard_on ActiveJob::DeserializationError
    discard_on ActiveStorage::IntegrityError

    def perform(blob, transformations)
      Storage::ActiveStorageRegistry.register_if_available! if defined?(Storage::ActiveStorageRegistry)
      blob.variant(**transformations.deep_symbolize_keys).processed
    rescue ActiveStorage::FileNotFoundError => error
      Storage::PublicCdnImageUrl.mark_transform_failed(
        blob: blob,
        transformations: transformations,
        error: error
      )
      Rails.logger.info("[storage_variant] arquivo ausente; transformacao descartada blob_id=#{blob.id}")
      nil
    rescue ActiveStorage::IntegrityError => error
      Storage::PublicCdnImageUrl.mark_transform_failed(
        blob: blob,
        transformations: transformations,
        error: error
      )
      raise
    end
  end
end

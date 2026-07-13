module Storage
  class PrepareSocialImageJob < ApplicationJob
    queue_as :media

    discard_on ActiveJob::DeserializationError
    discard_on ActiveStorage::FileNotFoundError

    def perform(habitation_id, attachment_id, tenant_id:, transformations:)
      tenant = Tenant.find_by(id: tenant_id)
      raise ArgumentError, "Tenant obrigatorio para preparar imagem social" unless tenant

      habitation = tenant.habitations.find_by(id: habitation_id)
      return unless habitation

      attachment = habitation.photos.attachments.includes(:blob).find_by(id: attachment_id)
      return unless attachment&.blob&.image?

      Current.set(tenant: tenant) do
        Storage::PublicPropertyPhoto.publish_attachment!(attachment)
        publish_variant!(attachment.blob, transformations)
      end
    end

    private

    def publish_variant!(blob, transformations)
      variant = blob.variant(**transformations.deep_symbolize_keys).processed
      return unless variant.respond_to?(:image)

      variant_image = variant.image
      return unless variant_image&.attached?

      Storage::PublicPropertyPhoto.publish_blob!(variant_image.blob, raise_errors: true)
    end
  end
end

module Storage
  class PublishPublicPropertyPhotosJob < ApplicationJob
    queue_as :default

    def perform(admin_user_id = nil, tenant_id = nil)
      tenant = Tenant.find_by(id: tenant_id) ||
        AdminUser.find_by(id: admin_user_id)&.tenant ||
        Current.tenant
      raise ArgumentError, "Tenant obrigatório para publicação de fotos públicas" if tenant.blank?

      admin_user = admin_user_id.present? ? tenant.admin_users.find_by(id: admin_user_id) : nil
      Current.tenant = tenant
      result = Storage::PublicPropertyPhotoPublisher.new(tenant: tenant).publish_all(track_progress: true)

      Rails.logger.info(
        "[storage_public_property_photos] admin_user_id=#{admin_user&.id} " \
        "#{Storage::PublicPropertyPhotoPublisher.result_message(result)}"
      )
    rescue StandardError => e
      Storage::PublicPropertyPhotoPublisher.write_progress(
        status: "failed",
        message: "Publicação interrompida: #{e.class}",
        finished_at: Time.current,
        tenant: Current.tenant
      )
      raise
    ensure
      Current.tenant = nil
    end
  end
end

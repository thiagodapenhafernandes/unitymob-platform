module Storage
  class PublishPublicPropertyPhotosJob < ApplicationJob
    queue_as :default

    def perform(admin_user_id = nil, tenant_id = nil)
      return fan_out_all_tenants! if admin_user_id.blank? && tenant_id.blank?

      tenant = Tenant.find_by(id: tenant_id) ||
        AdminUser.find_by(id: admin_user_id)&.tenant ||
        Current.tenant
      raise ArgumentError, "Tenant obrigatório para publicação de fotos públicas" if tenant.blank?

      admin_user = admin_user_id.present? ? tenant.admin_users.find_by(id: admin_user_id) : nil
      result = nil

      Current.set(tenant: tenant) do
        result = Storage::PublicPropertyPhotoPublisher.new(tenant: tenant).publish_all(track_progress: true)
      end

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
    end

    private

    def fan_out_all_tenants!
      tenant_ids = Tenant.active.pluck(:id)
      tenant_ids.each { |id| self.class.perform_later(nil, id) }

      Rails.logger.info("[storage_public_property_photos] fan_out tenants=#{tenant_ids.size}")
      { enqueued: tenant_ids.size }
    end
  end
end

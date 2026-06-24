module Storage
  class PublishPublicPropertyPhotosJob < ApplicationJob
    queue_as :default

    def perform(admin_user_id = nil)
      result = Storage::PublicPropertyPhotoPublisher.new.publish_all(track_progress: true)

      Rails.logger.info(
        "[storage_public_property_photos] admin_user_id=#{admin_user_id} " \
        "#{Storage::PublicPropertyPhotoPublisher.result_message(result)}"
      )
    rescue StandardError => e
      Storage::PublicPropertyPhotoPublisher.write_progress(
        status: "failed",
        message: "Publicação interrompida: #{e.class}",
        finished_at: Time.current
      )
      raise
    end
  end
end

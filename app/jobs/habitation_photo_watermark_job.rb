class HabitationPhotoWatermarkJob < ApplicationJob
  queue_as :media

  ORIGINAL_BLOB_PURGE_DELAY = 15.minutes

  discard_on ActiveJob::DeserializationError

  def perform(habitation_id, attachment_ids, property_setting_id = nil, tenant_id: nil)
    tenant = Tenant.find_by(id: tenant_id) || Current.tenant
    raise ArgumentError, "Tenant obrigatório para aplicar marca d'água" unless tenant
    habitation = tenant.habitations.find_by(id: habitation_id)
    return if habitation.blank?
    tenant ||= habitation.tenant

    Current.set(tenant: habitation.tenant) do
      setting = property_setting_id.present? ? PropertySetting.find_by(id: property_setting_id) : PropertySetting.instance
      return unless setting&.watermark_configured?

      attachments = habitation.photos.attachments.includes(:blob).where(id: Array(attachment_ids))
      attachments.find_each do |attachment|
        process_attachment(attachment, setting)
      end
    end
  end

  private

  def process_attachment(attachment, setting)
    blob = attachment.blob
    return if blob.blank?
    return if ActiveModel::Type::Boolean.new.cast(blob.metadata&.dig("salute_watermarked"))
    return unless blob.content_type.to_s.start_with?("image/")

    result = nil
    blob.open do |file|
      upload = BlobUpload.new(blob, file)
      result = Images::WatermarkProcessor.call(upload, setting: setting)
    end

    return unless result&.attachable.is_a?(Hash)

    new_blob = create_watermarked_blob(blob, result.attachable)
    Storage::PublicPropertyPhoto.publish_blob!(new_blob, raise_errors: true)
    attachment.update!(blob: new_blob)
    schedule_original_blob_purge(blob) unless blob.attachments.exists?
  ensure
    result&.tempfile&.close!
  end

  def create_watermarked_blob(original_blob, attachable)
    metadata = original_blob.metadata.to_h.merge(
      "salute_watermarked" => true,
      "salute_original_blob_id" => original_blob.id
    )

    ActiveStorage::Blob.create_and_upload!(
      io: attachable.fetch(:io),
      filename: attachable.fetch(:filename),
      content_type: attachable[:content_type].presence || original_blob.content_type,
      metadata: metadata
    )
  end

  def schedule_original_blob_purge(blob)
    Storage::SafePurgeJob.set(wait: ORIGINAL_BLOB_PURGE_DELAY).perform_later(blob.id)
  end

  class BlobUpload
    attr_reader :blob, :tempfile

    def initialize(blob, tempfile)
      @blob = blob
      @tempfile = tempfile
    end

    def original_filename
      blob.filename.to_s
    end

    def content_type
      blob.content_type.to_s
    end
  end
end

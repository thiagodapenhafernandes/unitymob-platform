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
      Storage::ActiveStorageRegistry.register_if_available! if defined?(Storage::ActiveStorageRegistry)

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
    return if ActiveModel::Type::Boolean.new.cast(blob.metadata&.dig("watermarked"))
    return unless blob.content_type.to_s.start_with?("image/")

    result = nil
    blob.open do |file|
      upload = BlobUpload.new(blob, file)
      result = Images::WatermarkProcessor.call(upload, setting: setting, raise_errors: true)
    end

    unless result&.attachable.is_a?(Hash)
      raise Images::WatermarkProcessor::ProcessingError, "Marca d'água não gerou arquivo processado para blob #{blob.id}"
    end

    new_blob = create_watermarked_blob(blob, result.attachable)
    Storage::PublicPropertyPhoto.publish_blob!(new_blob, raise_errors: true)
    attachment.update!(blob: new_blob)
    schedule_original_blob_purge(blob) unless blob.attachments.exists?
  rescue ActiveStorage::FileNotFoundError => error
    record_missing_source_blob(attachment, blob, error)
    Rails.logger.info("[habitation_photo_watermark] arquivo original ausente; marca d'agua descartada blob_id=#{blob&.id} attachment_id=#{attachment.id}")
    nil
  ensure
    result&.tempfile&.close!
  end

  def record_missing_source_blob(attachment, blob, error)
    Storage::BlobAuditRecorder.record!(
      blob: blob,
      attachment: attachment,
      action: "watermark_source_missing",
      source: "habitation_photo_watermark_job",
      metadata: {
        error: error.class.name
      }
    )
  end

  def create_watermarked_blob(original_blob, attachable)
    metadata = original_blob.metadata.to_h.merge(
      "watermarked" => true,
      "original_blob_id" => original_blob.id
    )
    service_name = original_blob.service_name.to_s.presence || ActiveStorage::Blob.service.name
    Storage::ActiveStorageRegistry.fetch!(service_name) unless service_name == "local"

    ActiveStorage::Blob.create_and_upload!(
      key: watermarked_key_for(original_blob, attachable.fetch(:filename)),
      io: attachable.fetch(:io),
      filename: attachable.fetch(:filename),
      content_type: attachable[:content_type].presence || original_blob.content_type,
      identify: false,
      metadata: metadata,
      service_name: service_name
    )
  end

  def watermarked_key_for(original_blob, filename)
    dirname = File.dirname(original_blob.key.to_s)
    basename = filename.to_s.parameterize.presence || original_blob.filename.to_s.parameterize.presence || "foto"
    key = "#{SecureRandom.base58(24)}-watermarked-#{basename}"

    dirname == "." ? key : [dirname, key].join("/")
  end

  def schedule_original_blob_purge(blob)
    Storage::BlobAuditRecorder.record!(
      blob: blob,
      action: "purge_scheduled",
      source: "habitation_photo_watermark_job",
      metadata: {
        delay_seconds: ORIGINAL_BLOB_PURGE_DELAY.to_i
      }
    )
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

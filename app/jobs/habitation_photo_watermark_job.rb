class HabitationPhotoWatermarkJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(habitation_id, attachment_ids, property_setting_id = nil)
    habitation = Habitation.find_by(id: habitation_id)
    return if habitation.blank?

    setting = property_setting_id.present? ? PropertySetting.find_by(id: property_setting_id) : PropertySetting.instance
    return unless setting&.watermark_configured?

    attachments = habitation.photos.attachments.includes(:blob).where(id: Array(attachment_ids))
    attachments.find_each do |attachment|
      process_attachment(attachment, setting)
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
    attachment.update!(blob: new_blob)
    blob.purge_later unless blob.attachments.exists?
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

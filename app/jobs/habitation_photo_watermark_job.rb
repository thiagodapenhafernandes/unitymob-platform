class HabitationPhotoWatermarkJob < ApplicationJob
  queue_as :media

  ORIGINAL_BLOB_PURGE_DELAY = 15.minutes
  MAX_ATTEMPTS = 3
  retry_on Images::WatermarkProcessor::ProcessingError, wait: 30.seconds, attempts: MAX_ATTEMPTS
  discard_on ActiveJob::DeserializationError

  def perform(habitation_id, attachment_ids, property_setting_id = nil, tenant_id: nil)
    tenant = tenant_id.present? ? Tenant.find_by(id: tenant_id) : Current.tenant
    raise ArgumentError, "Tenant obrigatório para aplicar marca d'água" unless tenant
    habitation = tenant.habitations.find_by(id: habitation_id)
    return unless habitation

    Current.set(tenant: tenant) do
      Storage::ActiveStorageRegistry.register_if_available! if defined?(Storage::ActiveStorageRegistry)
      setting = if property_setting_id.present?
        PropertySetting.where(tenant_id: tenant.id).find(property_setting_id)
      else
        PropertySetting.instance(tenant: tenant)
      end
      attachments = ActiveStorage::Attachment.where(record: habitation, name: %w[photos watermark_photos], id: Array(attachment_ids))
      failures = []
      attachments.find_each do |attachment|
        begin
          # Reload under a row lock: retries and concurrent workers cannot mark twice.
          attachment.with_lock do
            begin
              process_attachment(attachment, setting, tenant)
            rescue Images::WatermarkProcessor::ProcessingError => error
              attachment.blob.update!(metadata: attachment.blob.metadata.to_h.merge(
                "watermark_status" => (executions < MAX_ATTEMPTS ? "retrying" : "failed"),
                "watermark_error" => error.message
              ))
              failures << error
            end
          end
        rescue ActiveRecord::RecordNotFound
          next # Removed while this job was waiting for the lock.
        end
      end
      raise failures.first if failures.any?
    end
  end

  private

  def process_attachment(attachment, setting, tenant)
    blob = attachment.blob
    return if ActiveModel::Type::Boolean.new.cast(blob.metadata&.dig("watermarked"))
    raise Images::WatermarkProcessor::MissingWatermarkError, "Configure uma imagem de marca válida antes de tentar novamente." unless setting.watermark_configured?
    raise Images::WatermarkProcessor::ProcessingError, "O arquivo enviado não é uma foto compatível." unless blob.content_type.to_s.start_with?("image/")

    result = nil
    blob.open do |file|
      result = Images::WatermarkProcessor.call(BlobUpload.new(blob, file), setting: setting, raise_errors: true)
    end
    unless result&.attachable.is_a?(Hash)
      raise Images::WatermarkProcessor::ProcessingError, "Não foi possível gerar a foto com a marca."
    end

    new_blob = create_watermarked_blob(blob, result.attachable)
    if Storage::PublicPropertyPhoto.public_photos_enabled?(tenant: tenant)
      Storage::PublicPropertyPhoto.publish_blob!(new_blob, raise_errors: true)
    end
    attachment.update!(name: "photos", blob: new_blob)
    schedule_original_blob_purge(blob) unless blob.attachments.exists?
  rescue ActiveStorage::FileNotFoundError
    raise Images::WatermarkProcessor::ProcessingError, "A foto original não está disponível. Remova a pendência e envie a foto novamente."
  rescue Images::WatermarkProcessor::ProcessingError
    raise
  rescue StandardError => error
    raise Images::WatermarkProcessor::ProcessingError, "Falha ao processar ou armazenar a foto (#{error.class.name}). Tente novamente."
  ensure
    result&.tempfile&.close!
    # A failed replacement must not leave an unattached public object behind.
    if new_blob&.persisted? && !new_blob.attachments.exists?
      Storage::SafePurgeJob.perform_later(new_blob.id)
    end
  end

  def create_watermarked_blob(original_blob, attachable)
    metadata = original_blob.metadata.to_h.except("analyzed", "width", "height", "watermark_status", "watermark_error").merge(
      "watermarked" => true,
      "original_blob_id" => original_blob.id
    )
    service_name = original_blob.service_name.to_s.presence || ActiveStorage::Blob.service.name
    Storage::ActiveStorageRegistry.fetch!(service_name) unless service_name == "local"

    new_blob = ActiveStorage::Blob.build_after_unfurling(
      key: watermarked_key_for(original_blob, attachable.fetch(:filename)),
      io: attachable.fetch(:io), filename: attachable.fetch(:filename),
      content_type: attachable[:content_type].presence || original_blob.content_type,
      identify: false, metadata: metadata, service_name: service_name
    )
    new_blob.save!
    new_blob.upload_without_unfurling(attachable.fetch(:io))
    new_blob
  rescue StandardError
    Storage::SafePurgeJob.perform_later(new_blob.id) if new_blob&.persisted?
    raise
  end

  def watermarked_key_for(original_blob, filename)
    dirname = File.dirname(original_blob.key.to_s)
    basename = filename.to_s.parameterize.presence || "foto"
    key = "#{SecureRandom.base58(24)}-watermarked-#{basename}"
    dirname == "." ? key : [dirname, key].join("/")
  end

  def schedule_original_blob_purge(blob)
    Storage::BlobAuditRecorder.record!(blob: blob, action: "purge_scheduled", source: "habitation_photo_watermark_job",
      metadata: { delay_seconds: ORIGINAL_BLOB_PURGE_DELAY.to_i })
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

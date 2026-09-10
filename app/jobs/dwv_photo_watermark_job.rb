require "net/http"
require "stringio"

class DwvPhotoWatermarkJob < ApplicationJob
  queue_as :media
  retry_on StandardError, wait: 30.seconds, attempts: 3

  MAX_PHOTO_BYTES = 20.megabytes

  def perform(habitation_id, tenant_id:)
    tenant = Tenant.find(tenant_id)
    Current.set(tenant: tenant) do
      habitation = tenant.habitations.find_by(id: habitation_id)
      return unless habitation&.dwv_property?
      setting = PropertySetting.instance(tenant: tenant)
      return unless setting.watermark_configured?

      failures = []
      Array(habitation.pictures).each_with_index do |picture, index|
        payload = picture.is_a?(Hash) ? picture.stringify_keys : { "url" => picture }
        url = payload["url"].presence || payload["src"].presence || payload["link"]
        next if url.blank?
        uri = URI.parse(url.to_s) rescue nil
        next unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? &&
          Storage::PublicCdnImageUrl::TRUSTED_EXTERNAL_IMAGE_HOSTS.include?(uri.host)

        begin
          import_photo(habitation, payload, url, uri, index, setting)
        rescue StandardError => error
          failures << error
        end
      end
      raise failures.first if failures.any?
    end
  end

  private

  def import_photo(habitation, payload, url, uri, index, setting)
    blob = nil
    existing = source_attachment(habitation, url)
    unless existing
      bytes = download(uri)
      content_type = Marcel::MimeType.for(StringIO.new(bytes))
      raise "Formato de foto DWV inválido" unless content_type.in?(%w[image/jpeg image/png image/webp image/avif])

      service_name = Storage::Routing.service_name_for(record: habitation, name: "photos")
      Storage::ActiveStorageRegistry.fetch!(service_name) unless service_name.to_s.in?(%w[local test])
      blob = ActiveStorage::Blob.build_after_unfurling(
        io: StringIO.new(bytes), filename: "#{habitation.codigo}-#{index + 1}#{File.extname(uri.path)}",
        content_type: content_type, identify: false, service_name: service_name,
        metadata: payload.slice("ambiente", "ambiente_position").merge(source_url: url, tenant_id: habitation.tenant_id, position: index + 1, source: "dwv", watermark_status: "pending")
      )
      blob.save!
      blob.upload_without_unfurling(StringIO.new(bytes))
    end

    habitation.with_lock do
      existing = source_attachment(habitation, url)
      unless existing
        current_picture = Array(habitation.pictures).map { |entry| entry.is_a?(Hash) ? entry.stringify_keys : { "url" => entry } }
          .find { |entry| (entry["url"].presence || entry["src"].presence || entry["link"]) == url }
        return unless current_picture

        blob.update!(metadata: blob.metadata.except("ambiente", "ambiente_position").merge(current_picture.slice("ambiente", "ambiente_position")))
        habitation.watermark_photos.attach(blob)
        habitation.save!
        existing = ActiveStorage::Attachment.find_by!(record: habitation, name: "watermark_photos", blob_id: blob.id)
        if ActiveModel::Type::Boolean.new.cast(current_picture["site_hidden"])
          habitation.update!(site_hidden_photo_ids: Array(habitation.site_hidden_photo_ids) + [existing.id])
        end
      end
    end
    if existing.name == "watermark_photos"
      HabitationPhotoWatermarkJob.perform_later(habitation.id, [existing.id], setting.id, tenant_id: habitation.tenant_id)
    end
  ensure
    Storage::SafePurgeJob.perform_later(blob.id) if blob&.persisted? && !blob.attachments.exists?
  end

  def source_attachment(habitation, url)
    ActiveStorage::Attachment.where(record: habitation, name: %w[photos watermark_photos]).joins(:blob)
      .find_by("active_storage_blobs.metadata::jsonb ->> 'source_url' = ?", url)
  end

  def download(uri)
    bytes = +"".b
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
      http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
        raise "Falha ao baixar foto DWV (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
        response.read_body do |chunk|
          raise "Foto DWV excede 20 MB" if bytes.bytesize + chunk.bytesize > MAX_PHOTO_BYTES
          bytes << chunk
        end
      end
    end
    bytes
  end
end

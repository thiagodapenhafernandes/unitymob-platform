module Whatsapp
  class SyncTemplateMediaJob < ApplicationJob
    queue_as :default
    MAX_HEADER_MEDIA_DOWNLOAD_BYTES = 25.megabytes

    def perform(tenant_id, template_id)
      tenant = Tenant.find_by(id: tenant_id)
      return unless tenant

      Current.set(tenant: tenant) do
        record = tenant.whatsapp_templates.find_by(id: template_id)
        record&.with_lock { attach_synced_header_media(record) }
      end
    end

    private

    def attach_synced_header_media(record)
      return unless record.header_format.in?(%w[image video document])
      return if record.header_media_file.attached?

      url = record.header_media_handle.to_s
      return unless url.match?(%r{\Ahttps?://}i)

      response = HTTParty.get(url, timeout: 30)
      unless response.respond_to?(:success?) && response.success?
        Rails.logger.warn("[whatsapp templates sync] falha ao baixar midia do template=#{record.id} status=#{response.respond_to?(:code) ? response.code : "unknown"}")
        return
      end

      body = response.body.to_s
      if body.blank? || body.bytesize > MAX_HEADER_MEDIA_DOWNLOAD_BYTES
        Rails.logger.warn("[whatsapp templates sync] midia ignorada template=#{record.id} bytes=#{body.bytesize}")
        return
      end

      content_type = response.headers["content-type"].to_s.split(";").first.presence || content_type_for(record.header_format)
      record.header_media_file.attach(
        io: StringIO.new(body),
        filename: header_media_filename(url, record.header_format),
        content_type: content_type
      )
    rescue => e
      Rails.logger.warn("[whatsapp templates sync] nao foi possivel anexar midia do template=#{record.id}: #{e.class}: #{e.message}")
    end

    def header_media_filename(url, format)
      path = URI.parse(url).path.to_s
      basename = File.basename(path)
      return basename if basename.present? && basename.include?(".")

      "header_media#{extension_for(format)}"
    rescue URI::InvalidURIError
      "header_media#{extension_for(format)}"
    end

    def extension_for(format)
      {
        "image" => ".jpg",
        "video" => ".mp4",
        "document" => ".pdf"
      }.fetch(format.to_s, ".bin")
    end

    def content_type_for(format)
      {
        "image" => "image/jpeg",
        "video" => "video/mp4",
        "document" => "application/pdf"
      }.fetch(format.to_s, "application/octet-stream")
    end
  end
end

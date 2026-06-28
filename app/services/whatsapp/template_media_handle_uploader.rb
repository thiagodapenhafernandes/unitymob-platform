module Whatsapp
  class TemplateMediaHandleUploader
    ACCEPTED_TYPES = {
      "image" => %w[image/jpeg image/png],
      "video" => %w[video/mp4 video/3gpp],
      "document" => %w[application/pdf]
    }.freeze

    def self.call(template:, client: Whatsapp::CloudClient.new)
      new(template:, client:).call
    end

    def self.upload_attachable(attachable:, media_type:, client: Whatsapp::CloudClient.new)
      return { ok: false, error: "Anexe uma mídia de exemplo para aprovar este card." } if attachable.blank?

      new(template: nil, media_type:, client: client).upload_attachable(attachable)
    end

    def initialize(template:, client:, media_type: nil)
      @template = template
      @client = client
      @media_type = media_type.presence || template&.header_format.to_s
    end

    def call
      pending_upload = pending_attachable
      return upload_attachable(pending_upload) if pending_upload
      return error("Anexe uma mídia de exemplo para aprovar este cabeçalho.") unless @template.header_media_file.attached?

      upload_attachable(@template.header_media_file.blob)
    end

    def upload_attachable(attachable)
      content_type = attachable_content_type(attachable)
      return error("Formato incompatível com o tipo de mídia escolhido.") unless accepted_content_type?(content_type)

      io = attachable_io(attachable)
      result = @client.upload_template_media(
        file_name: attachable_file_name(attachable),
        content_type: content_type,
        byte_size: attachable_byte_size(attachable),
        io: io
      )
      result[:ok] ? { ok: true, handle: result[:handle] } : error(result[:error])
    end

    private

    def pending_attachable
      @template.attachment_changes["header_media_file"]&.attachable
    end

    def attachable_io(attachable)
      return attachable[:io] || attachable["io"] if attachable.is_a?(Hash)
      return attachable.tempfile if attachable.respond_to?(:tempfile)
      return attachable.open { |file| StringIO.new(file.read) } if attachable.respond_to?(:open)
      return StringIO.new(attachable.download) if attachable.respond_to?(:download)

      attachable
    end

    def attachable_file_name(attachable)
      if attachable.is_a?(Hash)
        filename = attachable[:filename] || attachable["filename"]
        return filename.to_s if filename.present?
      end
      return attachable.original_filename.to_s if attachable.respond_to?(:original_filename)
      return attachable.filename.to_s if attachable.respond_to?(:filename)

      "midia-template"
    end

    def attachable_byte_size(attachable)
      if attachable.is_a?(Hash)
        io = attachable[:io] || attachable["io"]
        return io.size if io.respond_to?(:size)
        return io.tempfile.size if io.respond_to?(:tempfile)
      end
      return attachable.tempfile.size if attachable.respond_to?(:tempfile)
      return attachable.byte_size if attachable.respond_to?(:byte_size)
      return attachable.size if attachable.respond_to?(:size)

      0
    end

    def attachable_content_type(attachable)
      if attachable.is_a?(Hash)
        content_type = attachable[:content_type] || attachable["content_type"]
        return content_type.to_s if content_type.present?
      end
      return attachable.content_type.to_s if attachable.respond_to?(:content_type)

      ""
    end

    def accepted_content_type?(content_type)
      ACCEPTED_TYPES.fetch(@media_type.to_s, []).include?(content_type.to_s)
    end

    def error(message)
      { ok: false, error: message.presence || "Não foi possível enviar a mídia para aprovação." }
    end
  end
end

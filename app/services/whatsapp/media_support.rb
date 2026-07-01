module Whatsapp
  module MediaSupport
    DOCUMENT_CONTENT_TYPES = %w[
      text/plain
      application/pdf
      application/msword
      application/vnd.ms-excel
      application/vnd.ms-powerpoint
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      application/vnd.openxmlformats-officedocument.presentationml.presentation
    ].freeze

    SUPPORTED_MEDIA = {
      "image" => {
        label: "Imagem",
        max_bytes: 5.megabytes,
        content_types: %w[image/jpeg image/png]
      },
      "video" => {
        label: "Vídeo",
        max_bytes: 16.megabytes,
        content_types: %w[video/mp4 video/3gpp]
      },
      "audio" => {
        label: "Áudio",
        max_bytes: 16.megabytes,
        content_types: %w[audio/aac audio/amr audio/mpeg audio/mp4 audio/ogg]
      },
      "document" => {
        label: "Documento",
        max_bytes: 100.megabytes,
        content_types: DOCUMENT_CONTENT_TYPES
      }
    }.freeze

    EXTENSION_OVERRIDES = {
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".mp4" => "video/mp4",
      ".3gp" => "video/3gpp",
      ".aac" => "audio/aac",
      ".amr" => "audio/amr",
      ".mp3" => "audio/mpeg",
      ".m4a" => "audio/mp4",
      ".ogg" => "audio/ogg",
      ".txt" => "text/plain",
      ".pdf" => "application/pdf",
      ".doc" => "application/msword",
      ".xls" => "application/vnd.ms-excel",
      ".ppt" => "application/vnd.ms-powerpoint",
      ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      ".pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    }.freeze

    SHORT_CONTENT_LABELS = {
      "text/plain" => "TXT",
      "application/pdf" => "PDF",
      "application/msword" => "DOC",
      "application/vnd.ms-excel" => "XLS",
      "application/vnd.ms-powerpoint" => "PPT",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => "DOCX",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "XLSX",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" => "PPTX",
      "image/jpeg" => "JPG",
      "image/png" => "PNG",
      "video/mp4" => "MP4",
      "video/3gpp" => "3GP",
      "audio/aac" => "AAC",
      "audio/amr" => "AMR",
      "audio/mpeg" => "MP3",
      "audio/mp4" => "M4A",
      "audio/ogg" => "OGG"
    }.freeze

    module_function

    def accept_attribute
      supported_content_types.join(",")
    end

    def supported_content_types
      SUPPORTED_MEDIA.values.flat_map { |config| config[:content_types] }.uniq
    end

    def type_for(content_type)
      content_type = content_type.to_s
      SUPPORTED_MEDIA.each do |type, config|
        return type if config[:content_types].include?(content_type)
      end

      nil
    end

    def label_for(type)
      SUPPORTED_MEDIA.dig(type.to_s, :label).to_s.presence || type.to_s.humanize
    end

    def short_label_for_content_type(content_type)
      SHORT_CONTENT_LABELS[content_type.to_s]
    end

    def validation_for(upload)
      content_type = resolved_content_type(upload)
      type = type_for(content_type)
      return { ok: false, error: unsupported_error } if type.blank?

      byte_size = upload_byte_size(upload)
      max_bytes = SUPPORTED_MEDIA.fetch(type).fetch(:max_bytes)
      return { ok: false, error: size_error(type, max_bytes) } if byte_size.positive? && byte_size > max_bytes

      { ok: true, type: type, content_type: content_type, max_bytes: max_bytes, byte_size: byte_size, file_name: original_filename(upload) }
    end

    def resolved_content_type(upload)
      explicit_content_type(upload).presence ||
        marcel_content_type(upload).presence ||
        extension_content_type(upload).presence ||
        "application/octet-stream"
    end

    def unsupported_error
      "Formato não suportado pela WhatsApp Cloud API. Use imagem JPG/PNG, vídeo MP4/3GP, áudio AAC/AMR/MP3/M4A/OGG ou documento TXT/PDF/DOC/DOCX/XLS/XLSX/PPT/PPTX."
    end

    def size_error(type, max_bytes)
      "#{label_for(type)} excede o limite da WhatsApp Cloud API (#{ActiveSupport::NumberHelper.number_to_human_size(max_bytes)})."
    end

    def explicit_content_type(upload)
      return unless upload.respond_to?(:content_type)

      content_type = upload.content_type.to_s
      return if content_type.blank? || content_type == "application/octet-stream"

      content_type
    end

    def marcel_content_type(upload)
      return unless defined?(Marcel::MimeType)

      io = if upload.respond_to?(:tempfile)
        upload.tempfile
      elsif upload.respond_to?(:path)
        upload
      end
      return unless io

      Marcel::MimeType.for(io, name: original_filename(upload))
    rescue
      nil
    end

    def extension_content_type(upload)
      extension = File.extname(original_filename(upload).to_s).downcase
      EXTENSION_OVERRIDES[extension]
    end

    def upload_byte_size(upload)
      return upload.byte_size if upload.respond_to?(:byte_size)
      return upload.size if upload.respond_to?(:size)
      return upload.tempfile.size if upload.respond_to?(:tempfile) && upload.tempfile.respond_to?(:size)

      0
    end

    def original_filename(upload)
      return upload.original_filename.to_s if upload.respond_to?(:original_filename)
      return upload.filename.to_s if upload.respond_to?(:filename)

      "arquivo"
    end
  end
end

module Whatsapp
  class TemplateMessageComponents
    Result = Struct.new(:ok?, :components, :error, keyword_init: true)

    def self.call(template:, variables:, client: nil)
      new(template, variables, client).call
    end

    def initialize(template, variables, client = nil)
      @template = template
      @variables = variables.to_h.transform_keys(&:to_s)
      @client = client
    end

    def call
      components = []
      add_header_component(components)
      add_body_component(components)
      add_buttons_components(components)
      add_carousel_component(components)

      Result.new(ok?: true, components: components.compact_blank, error: nil)
    rescue ArgumentError => e
      Result.new(ok?: false, components: [], error: e.message)
    end

    private

    attr_reader :template, :variables, :client

    def template_components
      @template_components ||= Array(template.components).map { |component| normalize_hash(component) }
    end

    def add_header_component(components)
      header = component_by_type("HEADER")
      return unless header

      format = header["format"].to_s.downcase
      return if format.blank? || format == "text" && placeholders(header["text"]).blank?

      parameters =
        if format == "text"
          text_parameters(header["text"])
        elsif %w[image video document].include?(format)
          [media_parameter(format, header_media_reference(header))]
        else
          []
        end
      return if parameters.blank?

      components << { type: "header", parameters: parameters }
    end

    def add_body_component(components)
      body = component_by_type("BODY")
      return unless body

      parameters = text_parameters(body["text"])
      return if parameters.blank?

      components << { type: "body", parameters: parameters }
    end

    def add_buttons_components(components)
      buttons = component_by_type("BUTTONS")
      Array(buttons&.dig("buttons")).each_with_index do |button, index|
        attrs = normalize_hash(button)
        next unless attrs["type"].to_s.casecmp("URL").zero?

        parameters = text_parameters(attrs["url"])
        next if parameters.blank?

        components << {
          type: "button",
          sub_type: "url",
          index: index.to_s,
          parameters: parameters
        }
      end
    end

    def add_carousel_component(components)
      carousel = component_by_type("CAROUSEL")
      return unless carousel

      cards = Array(carousel["cards"]).each_with_index.filter_map do |card, card_index|
        card_components = carousel_card_components(normalize_hash(card), card_index)
        next if card_components.blank?

        { card_index: card_index.to_s, components: card_components }
      end
      return if cards.blank?

      components << { type: "carousel", cards: cards }
    end

    def carousel_card_components(card, card_index)
      raw_components = Array(card["components"]).map { |component| normalize_hash(component) }
      components = []
      header = raw_components.find { |component| component["type"].to_s.casecmp("HEADER").zero? }
      body = raw_components.find { |component| component["type"].to_s.casecmp("BODY").zero? }
      buttons = raw_components.find { |component| component["type"].to_s.casecmp("BUTTONS").zero? }

      if header
        format = header["format"].to_s.downcase
        if %w[image video].include?(format)
          components << { type: "header", parameters: [media_parameter(format, carousel_media_reference(header, card_index))] }
        elsif format == "text"
          parameters = text_parameters(header["text"])
          components << { type: "header", parameters: parameters } if parameters.present?
        end
      end

      body_parameters = text_parameters(body&.dig("text"))
      components << { type: "body", parameters: body_parameters } if body_parameters.present?

      Array(buttons&.dig("buttons")).each_with_index do |button, index|
        attrs = normalize_hash(button)
        next unless attrs["type"].to_s.casecmp("URL").zero?

        parameters = text_parameters(attrs["url"])
        next if parameters.blank?

        components << {
          type: "button",
          sub_type: "url",
          index: index.to_s,
          parameters: parameters
        }
      end

      components
    end

    def component_by_type(type)
      template_components.find { |component| component["type"].to_s.casecmp(type).zero? }
    end

    def text_parameters(text)
      placeholders(text).map do |index|
        { type: "text", text: variable_value(index).presence || "-" }
      end
    end

    def placeholders(text)
      text.to_s.scan(/\{\{\s*(\d+)\s*\}\}/).flatten.map(&:to_i).uniq.sort
    end

    def variable_value(index)
      variables[index.to_s].to_s
    end

    def media_parameter(format, reference)
      type = format.to_s.downcase
      raise ArgumentError, "Modelo com cabeçalho de #{media_label(type)} precisa de uma mídia sincronizada para envio." if reference.blank?

      media = reference.match?(%r{\Ahttps?://}i) ? { link: reference } : { id: reference }
      media[:filename] = "documento" if type == "document" && media[:link].present?
      { type: type, type.to_sym => media }
    end

    def header_media_reference(header)
      uploaded_header_media_reference || Array(header.dig("example", "header_handle")).first.presence || template.header_media_handle.to_s.presence
    end

    def carousel_media_reference(header, card_index)
      Array(header.dig("example", "header_handle")).first.presence ||
        Array(template.carousel_cards).dig(card_index, "media_handle").to_s.presence
    end

    def uploaded_header_media_reference
      return @uploaded_header_media_reference if defined?(@uploaded_header_media_reference)

      @uploaded_header_media_reference = nil
      return unless client && template.header_media_file.attached?

      blob = template.header_media_file.blob
      media_type = template.header_format.to_s.downcase
      template.header_media_file.open do |file|
        upload = upload_header_media(file, blob, media_type)
        raise ArgumentError, upload[:error] unless upload[:ok]

        @uploaded_header_media_reference = upload[:media_id].presence
      end

      @uploaded_header_media_reference
    end

    def upload_header_media(file, blob, media_type)
      if media_type == "image" && blob.content_type.to_s == "image/png"
        upload_jpeg_header_media(file, blob)
      else
        client.upload_message_media(
          file_name: blob.filename.to_s,
          content_type: blob.content_type,
          type: media_type,
          io: file
        )
      end
    end

    def upload_jpeg_header_media(file, blob)
      require "mini_magick"

      output = Tempfile.new(["whatsapp-template-header-", ".jpg"])
      output.binmode

      convert_png_to_jpeg(file.path, output.path)
      output.rewind

      client.upload_message_media(
        file_name: jpeg_filename(blob.filename.to_s),
        content_type: "image/jpeg",
        type: "image",
        io: output
      )
    ensure
      output&.close
      output&.unlink
    end

    def convert_png_to_jpeg(input_path, output_path)
      MiniMagick::Tool.new("magick") do |command|
        command << input_path
        command.auto_orient
        command.background "white"
        command.alpha "remove"
        command.alpha "off"
        command.strip
        command.quality "85"
        command << "jpg:#{output_path}"
      end
    rescue MiniMagick::Error
      return if convert_png_to_jpeg_with_vips(input_path, output_path)

      raise ArgumentError, "A imagem PNG do cabeçalho não pôde ser convertida para JPEG. Anexe uma imagem JPG válida ao template antes de reenviar."
    end

    def convert_png_to_jpeg_with_vips(input_path, output_path)
      require "vips"

      image = Vips::Image.new_from_file(input_path, access: :sequential)
      image = image.flatten(background: [255, 255, 255]) if image.has_alpha?
      image.jpegsave(output_path, Q: 85, strip: true)
      true
    rescue LoadError, StandardError => e
      Rails.logger.warn("[whatsapp template media] fallback vips indisponivel: #{e.class}: #{e.message}")
      false
    end

    def jpeg_filename(filename)
      base = File.basename(filename.to_s, ".*").presence || "header_media"
      "#{base}.jpg"
    end

    def media_label(type)
      {
        "image" => "imagem",
        "video" => "vídeo",
        "document" => "documento"
      }.fetch(type.to_s, "mídia")
    end

    def normalize_hash(value)
      attrs = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
      attrs.deep_stringify_keys
    end
  end
end

require "mini_magick"

module Images
  class WatermarkProcessor
    Result = Struct.new(:attachable, :tempfile, keyword_init: true)

    GRAVITIES = {
      "bottom_left" => "SouthWest",
      "bottom_right" => "SouthEast",
      "center" => "Center"
    }.freeze

    def self.call(upload, setting:)
      new(upload, setting: setting).call
    end

    def initialize(upload, setting:)
      @upload = upload
      @setting = setting
    end

    def call
      return Result.new(attachable: upload) unless processable?

      setting.watermark_image.open do |watermark_file|
        image = MiniMagick::Image.open(upload.tempfile.path)
        image.auto_orient

        watermark = MiniMagick::Image.open(watermark_file.path)
        watermark.resize "#{watermark_width_for(image)}x"
        apply_watermark_opacity(watermark)

        output = build_tempfile
        composed = image.composite(watermark) do |config|
          config.compose "Over"
          config.gravity gravity
          config.geometry geometry_for(image)
        end
        composed.write(output.path)
        output.rewind

        Result.new(
          attachable: {
            io: output,
            filename: upload.original_filename,
            content_type: upload.content_type.presence || image.mime_type
          },
          tempfile: output
        )
      end
    rescue StandardError => error
      Rails.logger.warn("[WatermarkProcessor] Falha ao aplicar marca d'água em #{upload_filename}: #{error.class} - #{error.message}")
      Result.new(attachable: upload)
    end

    private

    attr_reader :upload, :setting

    def processable?
      setting&.watermark_configured? &&
        upload.respond_to?(:tempfile) &&
        upload.tempfile.present? &&
        upload_content_type.start_with?("image/")
    end

    def upload_content_type
      upload.content_type.to_s
    end

    def upload_filename
      upload.respond_to?(:original_filename) ? upload.original_filename : "arquivo"
    end

    def watermark_width_for(image)
      ratio = setting.watermark_size_percentage.to_i.clamp(
        PropertySetting::WATERMARK_SIZE_RANGE.begin,
        PropertySetting::WATERMARK_SIZE_RANGE.end
      ) / 100.0
      minimum = setting.watermark_position == "center" ? 180 : 120
      maximum = (image.width * (PropertySetting::WATERMARK_SIZE_RANGE.end / 100.0)).round

      [[(image.width * ratio).round, minimum].max, maximum].min
    end

    def apply_watermark_opacity(watermark)
      opacity = setting.watermark_opacity_percentage.to_i.clamp(
        PropertySetting::WATERMARK_OPACITY_RANGE.begin,
        PropertySetting::WATERMARK_OPACITY_RANGE.end
      ) / 100.0
      return if opacity >= 1.0

      watermark.combine_options do |config|
        config.alpha "set"
        config.channel "A"
        config.evaluate "multiply", opacity.to_s
        config.channel "RGBA"
      end
    end

    def gravity
      GRAVITIES.fetch(setting.watermark_position, GRAVITIES.fetch("bottom_left"))
    end

    def geometry_for(image)
      return "+0+0" if setting.watermark_position == "center"

      margin = [[(image.width * 0.035).round, 24].max, 64].min
      "+#{margin}+#{margin}"
    end

    def build_tempfile
      extension = File.extname(upload_filename.presence || "upload.jpg").presence || ".jpg"
      Tempfile.new(["watermarked-", extension]).tap(&:binmode)
    end
  end
end

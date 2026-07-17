# frozen_string_literal: true

# Ícones dos PWAs (admin e campo) derivados do logo do cliente (Identidade e
# Marca). O ícone é gerado como maskable, com fundo e respiro suficientes para
# os launchers de iOS/Android, usando as cores configuradas por tenant.
class PwaIconsController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  SIZES = [192, 512].freeze
  FALLBACK_PRIMARY = "#022B3A"
  FALLBACK_SECONDARY = "#053C5E"
  FALLBACK_ACCENT = "#BFAB25"

  def show
    size = params[:size].to_i
    return head :not_found unless SIZES.include?(size)

    response.headers["Cache-Control"] = "public, max-age=3600, stale-while-revalidate=86400"
    send_data icon_png(size), type: "image/png", disposition: "inline", filename: "pwa-icon-#{size}.png"
  rescue StandardError => e
    Rails.logger.warn("[PWA icon] falha ao gerar icone tenant=#{Current.tenant&.id}: #{e.class}: #{e.message}")
    raise if Rails.env.test?

    redirect_to "/field-icons/icon-#{size}.png"
  end

  private

  def icon_png(size)
    require "mini_magick"

    base = build_background(size)
    mark = build_brand_mark(size)
    return draw_default_mark(base, size) unless mark

    base = base.composite(mark) do |cmd|
      cmd.compose "Over"
      cmd.gravity "Center"
    end
    base.format("png")
    base.to_blob
  end

  def layout_setting
    @layout_setting ||= begin
      tenant = current_admin_user&.tenant || public_tenant
      LayoutSetting.with_attached_logo.with_attached_favicon.find_by(tenant: tenant) ||
        LayoutSetting.instance(tenant: tenant)
    end
  end

  def build_background(size)
    primary = normalized_hex(layout_setting.primary_color, FALLBACK_PRIMARY)
    secondary = normalized_hex(layout_setting.secondary_color, FALLBACK_SECONDARY)
    border = normalized_hex(layout_setting.accent_color, FALLBACK_ACCENT)
    radius = (size * 0.2).round
    stroke = [size * 0.018, 2].max.round
    inset = (stroke / 2.0).ceil

    file = Tempfile.new(["pwa-icon-background", ".png"])
    file.close
    run_image_tool do |magick|
      magick.size "#{size}x#{size}"
      magick << "gradient:#{primary}-#{secondary}"
      magick << file.path
    end
    image = MiniMagick::Image.open(file.path)
    image.combine_options do |cmd|
      cmd.alpha "set"
      cmd.fill "none"
      cmd.stroke border
      cmd.strokewidth stroke
      cmd.draw "roundrectangle #{inset},#{inset} #{size - inset - 1},#{size - inset - 1} #{radius},#{radius}"
    end
    image
  ensure
    file&.unlink
  end

  def build_brand_mark(size)
    file = nil
    output = nil

    begin
      attachment = brand_attachment
      return unless attachment&.attached?

      file = Tempfile.new(["pwa-brand-mark", File.extname(attachment.filename.to_s)])
      file.binmode
      file.write(attachment_bytes(attachment))
      file.flush

      output = Tempfile.new(["pwa-brand-mark-raster", ".png"])
      output.close
      run_image_tool do |magick|
        magick.background "none"
        magick << file.path
        magick.resize "#{brand_mark_size(size)}x#{brand_mark_size(size)}"
        magick.gravity "Center"
        magick.extent "#{brand_mark_size(size)}x#{brand_mark_size(size)}"
        magick << output.path
      end
      MiniMagick::Image.open(output.path)
    rescue MiniMagick::Error, ActiveStorage::FileNotFoundError => e
      Rails.logger.warn("[PWA icon] marca anexada invalida tenant=#{Current.tenant&.id}: #{e.class}: #{e.message}")
      nil
    ensure
      file&.close
      file&.unlink
      output&.unlink
    end
  end

  def brand_attachment
    layout_setting.favicon.attached? ? layout_setting.favicon : layout_setting.logo
  end

  def attachment_bytes(attachment)
    bytes = attachment.download
    return bytes unless attachment.content_type == "image/svg+xml"

    bytes.to_s
      .gsub(/stroke=(["'])null\1/i, 'stroke="none"')
      .gsub(/fill=(["'])null\1/i, 'fill="none"')
  end

  def brand_mark_size(size)
    (size * 0.58).round
  end

  def draw_default_mark(base, size)
    accent = normalized_hex(layout_setting.accent_color, FALLBACK_ACCENT)
    stroke = [size * 0.048, 6].max.round
    left = (size * 0.24).round
    right = (size * 0.76).round
    top = (size * 0.28).round
    mid = (size * 0.50).round
    bottom = (size * 0.70).round
    peak = (size * 0.50).round

    base.combine_options do |cmd|
      cmd.fill "none"
      cmd.stroke accent
      cmd.strokewidth stroke
      cmd.draw "polyline #{left},#{mid} #{peak},#{top} #{right},#{mid}"
      cmd.draw "polyline #{left},#{bottom} #{peak},#{mid} #{right},#{bottom}"
      cmd.draw "polyline #{left},#{(bottom + stroke * 2)} #{peak},#{(bottom - stroke * 2)} #{right},#{(bottom + stroke * 2)}"
    end
    base.format("png")
    base.to_blob
  end

  def normalized_hex(value, fallback)
    candidate = value.to_s.strip
    candidate.match?(/\A#[0-9a-fA-F]{6}\z/) ? candidate : fallback
  end

  def run_image_tool(&block)
    MiniMagick::Tool.new("magick", &block)
  rescue Errno::ENOENT, MiniMagick::Error
    MiniMagick::Tool.new("convert", &block)
  end
end

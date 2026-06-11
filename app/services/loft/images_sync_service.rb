require "open-uri"
require "set"

module Loft
  class ImagesSyncService
    def call(limit: 100)
      scope = Habitation.where.not(codigo: [nil, ""]).where.not(imovel_dwv: "Sim").order(updated_at: :desc).limit(limit.to_i.clamp(1, 500))

      synced = 0
      skipped = 0
      failed = 0

      scope.each do |habitation|
        result = sync_habitation_images(habitation)
        synced += result[:synced]
        skipped += result[:skipped]
        failed += result[:failed]
      end

      { processed: scope.size, synced: synced, skipped: skipped, failed: failed }
    end

    private

    def sync_habitation_images(habitation)
      pictures = habitation.pictures.is_a?(Array) ? habitation.pictures : []
      return { synced: 0, skipped: 1, failed: 0 } if pictures.blank?

      existing_filenames = habitation.photos.attachments.map { |att| att.filename.to_s }.to_set
      synced = 0
      skipped = 0
      failed = 0

      pictures.each_with_index do |pic, idx|
        url = picture_url(pic)
        next if url.blank?

        filename = picture_filename(url, "vista_#{habitation.id}_#{idx + 1}.jpg")
        if existing_filenames.include?(filename)
          skipped += 1
          next
        end

        begin
          io = URI.open(url, read_timeout: 20, open_timeout: 10)
          habitation.photos.attach(io: io, filename: filename)
          synced += 1
          existing_filenames << filename
        rescue => e
          failed += 1
          Rails.logger.error("[Loft::ImagesSyncService] habitation=#{habitation.id} file=#{filename} erro=#{e.message}")
        end
      end

      { synced: synced, skipped: skipped, failed: failed }
    end

    def picture_url(pic)
      return pic if pic.is_a?(String)
      return unless pic.is_a?(Hash)

      pic["url"] || pic[:url] || pic["Foto"] || pic[:Foto]
    end

    def picture_filename(url, fallback)
      uri = URI.parse(url)
      name = File.basename(uri.path.presence || fallback)
      name.present? ? name : fallback
    rescue
      fallback
    end
  end
end

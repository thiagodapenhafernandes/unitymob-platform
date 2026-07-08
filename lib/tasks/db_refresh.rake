# frozen_string_literal: true

require "shellwords"

module DbRefreshPropertyPhotos
  module_function

  DEFAULT_REMOTE_STORAGE = "salute@143.110.138.67:/home/salute/deploy/shared/storage/"

  def truthy_env?(value)
    value.to_s.strip.downcase.in?(["1", "true", "yes", "y", "on"])
  end

  def register_storage_services
    Storage::ActiveStorageRegistry.register_if_available! if defined?(Storage::ActiveStorageRegistry)
  end

  def ensure_development_or_forced!
    return if Rails.env.development? || truthy_env?(ENV["FORCE"])

    abort "[db_refresh:repair_property_photos] bloqueado fora de development. Use FORCE=true se souber exatamente o impacto."
  end

  def habitation_photo_attachments
    ActiveStorage::Attachment
      .includes(:blob)
      .where(record_type: "Habitation", name: "photos")
      .order(:id)
  end

  def blob_service_counts
    ActiveStorage::Blob
      .joins("INNER JOIN active_storage_attachments ON active_storage_attachments.blob_id = active_storage_blobs.id")
      .where(active_storage_attachments: { record_type: "Habitation", name: "photos" })
      .group(:service_name)
      .order(:service_name)
      .count
  end

  def disk_blob?(blob)
    blob.service.class.name == "ActiveStorage::Service::DiskService"
  rescue KeyError
    register_storage_services
    blob.service.class.name == "ActiveStorage::Service::DiskService"
  end

  def storage_object_exists?(blob)
    blob.service.exist?(blob.key)
  rescue StandardError
    false
  end

  def missing_disk_photo_summary(limit:)
    scanned = 0
    missing = 0
    relation = habitation_photo_attachments
      .joins(:blob)
      .where(active_storage_blobs: { service_name: "local" })
    disk = relation.unscope(:order).count

    relation.find_each(batch_size: 100) do |attachment|
      break if limit.positive? && scanned >= limit

      blob = attachment.blob
      next unless blob
      next unless disk_blob?(blob)

      scanned += 1
      missing += 1 unless storage_object_exists?(blob)
    end

    { scanned: scanned, disk: disk, missing: missing }
  end

  def rsync_remote_storage!(apply:)
    remote = ENV.fetch("REMOTE_STORAGE_RSYNC", DEFAULT_REMOTE_STORAGE)
    local = ENV.fetch("LOCAL_STORAGE_PATH", Rails.root.join("storage/").to_s)
    command = ["rsync", "-a", "--ignore-existing", remote, local]

    puts "[db_refresh:repair_property_photos] rsync #{remote} -> #{local} apply=#{apply}"
    return true unless apply

    system(*command).tap do |success|
      abort "[db_refresh:repair_property_photos] rsync falhou: #{command.shelljoin}" unless success
    end
  end

  def run_source_repair!(apply:)
    return unless truthy_env?(ENV.fetch("REPAIR_FROM_SOURCE", "true"))

    ENV["APPLY"] = apply ? "true" : "false"
    ENV["LIMIT"] ||= ENV.fetch("REPAIR_LIMIT", "100")
    Rake::Task["images:repair_missing_habitation_photo_blobs"].reenable
    Rake::Task["images:repair_missing_habitation_photo_blobs"].invoke
  end
end

namespace :db_refresh do
  desc "Diagnostica fotos de imóveis após refresh de banco local"
  task property_photo_health: :environment do
    DbRefreshPropertyPhotos.register_storage_services

    limit = ENV.fetch("CHECK_LIMIT", "500").to_i
    service_counts = DbRefreshPropertyPhotos.blob_service_counts
    disk_summary = DbRefreshPropertyPhotos.missing_disk_photo_summary(limit: limit)

    puts "[db_refresh:property_photo_health] active_storage_service=#{Rails.application.config.active_storage.service}"
    puts "[db_refresh:property_photo_health] habitation_photo_blobs_by_service=#{service_counts.inspect}"
    puts "[db_refresh:property_photo_health] disk_check limit=#{limit.positive? ? limit : 'all'} scanned=#{disk_summary[:scanned]} disk=#{disk_summary[:disk]} missing=#{disk_summary[:missing]}"
  end

  desc "Repara fotos de imóveis após importar banco de produção no ambiente local"
  task repair_property_photos: :environment do
    DbRefreshPropertyPhotos.ensure_development_or_forced!
    DbRefreshPropertyPhotos.register_storage_services

    apply = DbRefreshPropertyPhotos.truthy_env?(ENV.fetch("APPLY", "false"))
    limit = ENV.fetch("CHECK_LIMIT", "500").to_i
    service_counts = DbRefreshPropertyPhotos.blob_service_counts
    disk_summary = DbRefreshPropertyPhotos.missing_disk_photo_summary(limit: limit)

    puts "[db_refresh:repair_property_photos] apply=#{apply}"
    puts "[db_refresh:repair_property_photos] habitation_photo_blobs_by_service=#{service_counts.inspect}"
    puts "[db_refresh:repair_property_photos] disk_check limit=#{limit.positive? ? limit : 'all'} scanned=#{disk_summary[:scanned]} disk=#{disk_summary[:disk]} missing=#{disk_summary[:missing]}"

    if disk_summary[:missing].positive?
      DbRefreshPropertyPhotos.rsync_remote_storage!(apply: apply)
    else
      puts "[db_refresh:repair_property_photos] nenhum blob Disk ausente encontrado na amostra."
    end

    DbRefreshPropertyPhotos.run_source_repair!(apply: apply)

    puts "[db_refresh:repair_property_photos] concluido"
  end
end

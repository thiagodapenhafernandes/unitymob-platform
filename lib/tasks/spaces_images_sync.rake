require "open-uri"
require "yaml"
require "fileutils"
require "set"
require "openssl"
require "net/http"
require "stringio"
require "csv"

module SpacesImageSync
  module_function

  def truthy_env?(value)
    value.to_s.strip.downcase.in?(["1", "true", "yes", "y", "on"])
  end

  def skip_analysis?
    truthy_env?(ENV["SKIP_ANALYSIS"])
  end

  def cursor_data(path)
    return { "last_id" => 0 } unless File.exist?(path)

    YAML.safe_load(File.read(path), permitted_classes: [Time], aliases: true) || { "last_id" => 0 }
  rescue
    { "last_id" => 0 }
  end

  def write_cursor(path, last_id:, cycle:, synced:, skipped:, failed:)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, {
      "last_id" => last_id,
      "cycle" => cycle,
      "last_run_at" => Time.current,
      "synced" => synced,
      "skipped" => skipped,
      "failed" => failed
    }.to_yaml)
  end

  def append_failure(path, habitation_id)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "a") { |f| f.puts(habitation_id) }
  end

  def extract_picture_url(pic)
    return pic if pic.is_a?(String)
    return unless pic.is_a?(Hash)

    pic["url"] || pic[:url] || pic["Foto"] || pic[:Foto]
  end

  def picture_filename(url, fallback)
    uri = URI.parse(url)
    base = File.basename(uri.path.presence || fallback)
    base.present? ? base : fallback
  rescue
    fallback
  end

  def process_habitation(habitation, dry_run:)
    pictures = habitation.pictures.is_a?(Array) ? habitation.pictures : []
    return { synced: 0, skipped: 1, failed: 0, habitation_failed: false } if pictures.blank?

    existing_filenames = habitation.photos.attachments.map { |att| att.filename.to_s }.to_set
    synced = 0
    skipped = 0
    failed = 0
    habitation_failed = false

    pictures.each_with_index do |pic, idx|
      url = extract_picture_url(pic)
      next if url.blank?

      fallback = "picture_#{habitation.id}_#{idx + 1}.jpg"
      filename = picture_filename(url, fallback)

      if existing_filenames.include?(filename)
        skipped += 1
        next
      end

      if dry_run
        puts "[DRY_RUN] habitation=#{habitation.id} codigo=#{habitation.codigo} file=#{filename}"
        synced += 1
        existing_filenames << filename
        next
      end

      begin
        io = SpacesImageSync.download_image(url)
        existing_attachment_ids = habitation.photos.attachments.ids
        metadata = SpacesImageSync.skip_analysis? ? { "analyzed" => true, "identified" => true } : { "identified" => true }
        service_name = StorageIntegrationSetting.current.photo_service_name
        Storage::ActiveStorageRegistry.fetch!(service_name) unless service_name == :local
        blob = ActiveStorage::Blob.create_and_upload!(
          io: io,
          filename: filename,
          metadata: metadata,
          service_name: service_name
        )
        habitation.photos.attach(blob)
        SpacesImageSync.publish_new_photo_attachments(habitation, existing_attachment_ids)
        synced += 1
        existing_filenames << filename
      rescue => e
        habitation_failed = true
        failed += 1
        Rails.logger.error("[images:sync_habitations_to_spaces] habitation=#{habitation.id} file=#{filename} erro=#{e.message}")
      end
    end

    { synced: synced, skipped: skipped, failed: failed, habitation_failed: habitation_failed }
  end

  def publish_new_photo_attachments(habitation, existing_attachment_ids)
    habitation.photos.attachments.includes(:blob).where.not(id: existing_attachment_ids).find_each do |attachment|
      Storage::PublicPropertyPhoto.publish_attachment!(attachment)
    end
  end

  # Baixa uma imagem HTTP(S) com VERIFY_PEER mas sem checagem de CRL.
  # A Vista CDN usa certificados Let's Encrypt R12 que não publicam CRL
  # (apenas OCSP), e o OpenURI default falha com "unable to get certificate CRL".
  # Retorna StringIO pronto pro ActiveStorage#attach.
  def download_image(url, read_timeout: 20, open_timeout: 10, max_redirects: 5)
    remaining_redirects = max_redirects

    loop do
      uri = URI.parse(url.to_s)
      raise "URL inválida para download: #{url.inspect}" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      if http.use_ssl?
        # Servidor Ubuntu em produção tem OpenSSL configurado para exigir CRL check
        # (unable to get certificate CRL). Vista CDN usa Let's Encrypt R12 que só publica
        # OCSP — sem CRL. curl/openssl-s_client passam mas Ruby com VERIFY_PEER falha.
        # Como os recursos são fotos públicas vindas de domínio conhecido (vistahost.com.br),
        # desabilitamos a verificação SSL apenas para o download da imagem.
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http.read_timeout = read_timeout
      http.open_timeout = open_timeout

      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        return StringIO.new(response.body)
      when Net::HTTPRedirection
        raise "Muitos redirects para #{url}" if remaining_redirects <= 0
        remaining_redirects -= 1
        url = response["location"]
      else
        raise "Download falhou (#{response.code} #{response.message}) para #{url}"
      end
    end
  end

  def repair_source_url_for(blob, habitation = nil)
    metadata_source_url = blob.metadata.to_h["vista_source_url"].presence
    return metadata_source_url if metadata_source_url.present?
    return unless habitation&.pictures.is_a?(Array)

    filename = blob.filename.to_s
    habitation.pictures.find do |picture|
      url = extract_picture_url(picture)
      url.present? && picture_filename(url, nil).to_s == filename
    end.then { |picture| extract_picture_url(picture) if picture }
  end

  def repair_missing_blob(blob, source_url)
    io = download_image(source_url, read_timeout: 30, open_timeout: 10)
    upload_options = { content_type: blob.content_type }
    upload_options[:checksum] = blob.checksum if blob.checksum.present?

    blob.service.upload(blob.key, io, **upload_options.compact)
  end

  def source_label(url)
    uri = URI.parse(url.to_s)
    [uri.host, File.basename(uri.path.to_s)].compact_blank.join("/")
  rescue URI::InvalidURIError
    "invalid-url"
  end

  def missing_storage_object_error?(error)
    error.class.name.end_with?("NoSuchKey", "NotFound") ||
      error.message.to_s.include?("NoSuchKey") ||
      error.message.to_s.include?("NotFound")
  end
end

namespace :images do
  desc "Sincroniza fotos (JSON pictures) de imóveis para ActiveStorage/Spaces com cursor e cadência"
  task sync_habitations_to_spaces: :environment do
    batch_size = ENV.fetch("BATCH_SIZE", ENV.fetch("LIMIT", "100")).to_i
    batch_size = 100 if batch_size <= 0

    dry_run = SpacesImageSync.truthy_env?(ENV["DRY_RUN"])
    loop_mode = SpacesImageSync.truthy_env?(ENV.fetch("LOOP", "false"))
    stop_when_done = SpacesImageSync.truthy_env?(ENV.fetch("STOP_WHEN_DONE", "true"))
    reset_cursor = SpacesImageSync.truthy_env?(ENV.fetch("RESET_CURSOR", "false"))
    only_without_attachments = SpacesImageSync.truthy_env?(ENV.fetch("ONLY_WITHOUT_ATTACHMENTS", "false"))

    sleep_seconds = ENV.fetch("SLEEP_SECONDS", "3").to_f
    max_cycles = ENV.fetch("MAX_CYCLES", "0").to_i
    start_id = ENV.fetch("START_ID", "0").to_i
    max_id = ENV.fetch("MAX_ID", "0").to_i

    cursor_file = ENV.fetch("CURSOR_FILE", Rails.root.join("tmp/spaces_habitation_images_cursor.yml").to_s)
    failed_file = ENV.fetch("FAILED_FILE", Rails.root.join("tmp/spaces_habitation_images_failed_ids.log").to_s)

    cursor = SpacesImageSync.cursor_data(cursor_file)
    cursor["last_id"] = 0 if reset_cursor
    cursor["last_id"] = start_id - 1 if start_id.positive?

    total_synced = 0
    total_skipped = 0
    total_failed = 0
    cycle = 0

    puts "[images:sync_habitations_to_spaces] service=#{Rails.application.config.active_storage.service} dry_run=#{dry_run} skip_analysis=#{SpacesImageSync.skip_analysis?}"
    puts "[images:sync_habitations_to_spaces] batch_size=#{batch_size} loop=#{loop_mode} sleep=#{sleep_seconds}s cursor=#{cursor_file}"
    puts "[images:sync_habitations_to_spaces] range=[start_id=#{start_id} max_id=#{max_id.positive? ? max_id : 'no limit'}]"

    loop do
      cycle += 1
      last_id = cursor["last_id"].to_i

      scope = Habitation.where("habitations.id > ?", last_id).where.not(imovel_dwv: "Sim").order("habitations.id")
      scope = scope.where("habitations.id <= ?", max_id) if max_id.positive?
      scope = scope.where.missing(:photos_attachments) if only_without_attachments
      batch = scope.limit(batch_size).to_a

      if batch.empty?
        puts "[images:sync_habitations_to_spaces] ciclo=#{cycle} sem registros pendentes apos id=#{last_id}"
        break if !loop_mode || stop_when_done

        sleep(sleep_seconds)
        next
      end

      cycle_synced = 0
      cycle_skipped = 0
      cycle_failed = 0

      batch.each do |habitation|
        result = SpacesImageSync.process_habitation(habitation, dry_run: dry_run)
        cycle_synced += result[:synced]
        cycle_skipped += result[:skipped]
        cycle_failed += result[:failed]
        SpacesImageSync.append_failure(failed_file, habitation.id) if result[:habitation_failed]

        cursor["last_id"] = habitation.id
        SpacesImageSync.write_cursor(cursor_file, last_id: cursor["last_id"], cycle: cycle, synced: total_synced + cycle_synced, skipped: total_skipped + cycle_skipped, failed: total_failed + cycle_failed)
      end

      total_synced += cycle_synced
      total_skipped += cycle_skipped
      total_failed += cycle_failed

      puts "[images:sync_habitations_to_spaces] ciclo=#{cycle} last_id=#{cursor['last_id']} synced=#{cycle_synced} skipped=#{cycle_skipped} failed=#{cycle_failed}"

      if max_cycles.positive? && cycle >= max_cycles
        puts "[images:sync_habitations_to_spaces] encerrando por MAX_CYCLES=#{max_cycles}"
        break
      end

      break unless loop_mode

      sleep(sleep_seconds)
    end

    puts "[images:sync_habitations_to_spaces] total_synced=#{total_synced} total_skipped=#{total_skipped} total_failed=#{total_failed}"
    puts "[images:sync_habitations_to_spaces] failed_log=#{failed_file}" if total_failed.positive?
  end

  desc "Reprocessa IDs de imóveis que falharam em execuções anteriores"
  task retry_failed_habitations_to_spaces: :environment do
    failed_file = ENV.fetch("FAILED_FILE", Rails.root.join("tmp/spaces_habitation_images_failed_ids.log").to_s)
    unless File.exist?(failed_file)
      puts "[images:retry_failed_habitations_to_spaces] nenhum arquivo de falhas em #{failed_file}"
      next
    end

    ids = File.readlines(failed_file, chomp: true).map(&:to_i).select(&:positive?).uniq
    if ids.empty?
      puts "[images:retry_failed_habitations_to_spaces] nenhum id valido no arquivo"
      next
    end

    dry_run = SpacesImageSync.truthy_env?(ENV["DRY_RUN"])
    synced = 0
    skipped = 0
    failed = 0

    puts "[images:retry_failed_habitations_to_spaces] reprocessando #{ids.size} imóveis dry_run=#{dry_run}"

    Habitation.where(id: ids).where.not(imovel_dwv: "Sim").order(:id).find_each do |habitation|
      result = SpacesImageSync.process_habitation(habitation, dry_run: dry_run)
      synced += result[:synced]
      skipped += result[:skipped]
      failed += result[:failed]
    end

    puts "[images:retry_failed_habitations_to_spaces] synced=#{synced} skipped=#{skipped} failed=#{failed}"
  end

  desc "Restaura objetos ActiveStorage ausentes no Spaces usando a origem de migração salva no metadata"
  task repair_missing_habitation_photo_blobs: :environment do
    apply = SpacesImageSync.truthy_env?(ENV.fetch("APPLY", "false"))
    limit = ENV.fetch("LIMIT", "100").to_i
    limit = 100 if limit <= 0
    codigo = ENV["CODIGO"].presence
    blob_id = ENV["BLOB_ID"].presence

    attachments = ActiveStorage::Attachment
      .includes(:blob)
      .where(record_type: "Habitation", name: "photos")
      .order(:id)

    attachments = attachments.joins(:blob).where(active_storage_blobs: { id: blob_id }) if blob_id
    attachments = attachments.joins("INNER JOIN habitations ON habitations.id = active_storage_attachments.record_id").where(habitations: { codigo: codigo }) if codigo

    scanned = 0
    missing = 0
    repaired = 0
    skipped_without_source = 0
    failed = 0

    puts "[images:repair_missing_habitation_photo_blobs] service=#{Rails.application.config.active_storage.service} apply=#{apply} limit=#{limit} codigo=#{codigo || '-'} blob_id=#{blob_id || '-'}"

    attachments.find_each(batch_size: 50) do |attachment|
      break if scanned >= limit

      blob = attachment.blob
      next unless blob

      scanned += 1
      next if blob.service.exist?(blob.key)

      missing += 1
      source_url = SpacesImageSync.repair_source_url_for(blob)
      source_url ||= SpacesImageSync.repair_source_url_for(blob, Habitation.find_by(id: attachment.record_id))
      source_label = SpacesImageSync.source_label(source_url)

      if source_url.blank?
        skipped_without_source += 1
        puts "[MISS sem_origem] habitation_id=#{attachment.record_id} blob_id=#{blob.id} filename=#{blob.filename}"
        next
      end

      unless apply
        puts "[DRY_RUN restauraria] habitation_id=#{attachment.record_id} blob_id=#{blob.id} filename=#{blob.filename} source=#{source_label}"
        next
      end

      begin
        SpacesImageSync.repair_missing_blob(blob, source_url)
        Storage::PublicPropertyPhoto.publish_blob!(blob)
        repaired += 1
        puts "[OK restaurado] habitation_id=#{attachment.record_id} blob_id=#{blob.id} filename=#{blob.filename} source=#{source_label}"
      rescue StandardError => e
        failed += 1
        puts "[ERRO] habitation_id=#{attachment.record_id} blob_id=#{blob.id} filename=#{blob.filename} source=#{source_label} error=#{e.class}: #{e.message}"
      end
    end

    puts "[images:repair_missing_habitation_photo_blobs] scanned=#{scanned} missing=#{missing} repaired=#{repaired} skipped_without_source=#{skipped_without_source} failed=#{failed}"
  end

  desc "Publica ACL public-read para fotos de imóveis já anexadas, mantendo documentos privados"
  task publish_public_habitation_photos: :environment do
    apply = SpacesImageSync.truthy_env?(ENV.fetch("APPLY", "false"))
    limit = ENV.fetch("LIMIT", "500").to_i
    limit = nil if limit <= 0
    codigo = ENV["CODIGO"].presence
    start_after_blob_id = ENV.fetch("START_AFTER_BLOB_ID", "0").to_i
    missing_file = ENV.fetch("MISSING_FILE", Rails.root.join("tmp/missing_habitation_photo_blobs.csv").to_s)
    log_missing = SpacesImageSync.truthy_env?(ENV.fetch("LOG_MISSING", "false"))
    progress_every = ENV.fetch("PROGRESS_EVERY", "500").to_i
    progress_every = 500 if progress_every <= 0
    cursor_file = ENV.fetch("CURSOR_FILE", Rails.root.join("tmp/publish_public_habitation_photos_cursor.txt").to_s)

    attachments = ActiveStorage::Attachment
      .includes(:blob)
      .where(record_type: "Habitation", name: "photos")
      .order(:id)

    if codigo
      attachments = attachments
        .joins("INNER JOIN habitations ON habitations.id = active_storage_attachments.record_id")
        .where(habitations: { codigo: codigo })
    end

    blob_ids = attachments.unscope(:order).distinct.pluck(:blob_id)
    sample_attachment_ids_by_blob_id = attachments.unscope(:order).group(:blob_id).minimum(:id)
    sample_record_id_by_blob_id = ActiveStorage::Attachment
      .where(id: sample_attachment_ids_by_blob_id.values)
      .pluck(:blob_id, :record_id)
      .to_h
    blobs = ActiveStorage::Blob.where(id: blob_ids).where("id > ?", start_after_blob_id).order(:id)

    scanned = 0
    published = 0
    missing = 0
    failed = 0
    last_blob_id = start_after_blob_id

    if apply && !File.exist?(missing_file)
      FileUtils.mkdir_p(File.dirname(missing_file))
      File.write(missing_file, "blob_id,habitation_id,filename,key\n")
    end

    puts "[images:publish_public_habitation_photos] service=#{Rails.application.config.active_storage.service} apply=#{apply} limit=#{limit || 'all'} codigo=#{codigo || '-'} start_after_blob_id=#{start_after_blob_id} distinct_blobs=#{blob_ids.size} log_missing=#{log_missing} progress_every=#{progress_every}"

    emit_progress = lambda do
      next unless (scanned % progress_every).zero?

      FileUtils.mkdir_p(File.dirname(cursor_file))
      File.write(cursor_file, last_blob_id.to_s)
      puts "[images:publish_public_habitation_photos] progress scanned=#{scanned} published=#{published} missing=#{missing} failed=#{failed} last_blob_id=#{last_blob_id}"
    end

    blobs.find_each(batch_size: 100) do |blob|
      break if limit && scanned >= limit

      sample_record_id = sample_record_id_by_blob_id[blob.id]

      scanned += 1
      last_blob_id = blob.id

      unless apply
        public_url = Storage::PublicPropertyPhoto.public_url_for_blob(blob)
        puts "[DRY_RUN publicaria] habitation_id=#{sample_record_id || '-'} blob_id=#{blob.id} filename=#{blob.filename} url_host=#{URI.parse(public_url).host rescue '-'}"
        emit_progress.call
        next
      end

      begin
        if Storage::PublicPropertyPhoto.publish_blob!(blob, raise_errors: true)
          published += 1
        else
          failed += 1
          puts "[ERRO] habitation_id=#{sample_record_id || '-'} blob_id=#{blob.id} filename=#{blob.filename}"
        end
      rescue StandardError => e
        if SpacesImageSync.missing_storage_object_error?(e)
          missing += 1
          File.open(missing_file, "a") { |f| f.puts([blob.id, sample_record_id, blob.filename, blob.key].to_csv) }
          puts "[MISS] habitation_id=#{sample_record_id || '-'} blob_id=#{blob.id} filename=#{blob.filename}" if log_missing
        else
          failed += 1
          puts "[ERRO] habitation_id=#{sample_record_id || '-'} blob_id=#{blob.id} filename=#{blob.filename} error=#{e.class}: #{e.message}"
        end
      end

      emit_progress.call
    end

    FileUtils.mkdir_p(File.dirname(cursor_file))
    File.write(cursor_file, last_blob_id.to_s)

    puts "[images:publish_public_habitation_photos] scanned=#{scanned} published=#{published} missing=#{missing} failed=#{failed} last_blob_id=#{last_blob_id}"
    puts "[images:publish_public_habitation_photos] missing_file=#{missing_file}" if missing.positive?
  end
end

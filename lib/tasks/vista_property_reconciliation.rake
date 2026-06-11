namespace :vista do
  desc "Reconcilia imóveis locais com a API atual da Vista, reaproveitando arquivos já baixados quando possível"
  task reconcile_properties: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
    limit = ENV.fetch("LIMIT", "10").to_i
    explicit_codes = ENV.fetch("CODES", "").split(",").map(&:strip).reject(&:blank?)
    codes_file = ENV["CODES_FILE"].presence

    codigos = if explicit_codes.any?
                explicit_codes
              elsif codes_file
                File.readlines(codes_file, chomp: true).map(&:strip).reject(&:blank?).uniq
              else
                scope = Habitation.where("COALESCE(NULLIF(vista_codigo, ''), codigo) ~ ?", "^[0-9]+$")
                if ENV["START_BELOW"].present?
                  scope = scope.where("COALESCE(NULLIF(vista_codigo, ''), codigo)::bigint < ?", ENV.fetch("START_BELOW").to_i)
                end
                if ENV["START_AT_OR_BELOW"].present?
                  scope = scope.where("COALESCE(NULLIF(vista_codigo, ''), codigo)::bigint <= ?", ENV.fetch("START_AT_OR_BELOW").to_i)
                end
                if ENV["MIN_CODE"].present?
                  scope = scope.where("COALESCE(NULLIF(vista_codigo, ''), codigo)::bigint >= ?", ENV.fetch("MIN_CODE").to_i)
                end
                if ENV["MAX_CODE"].present?
                  scope = scope.where("COALESCE(NULLIF(vista_codigo, ''), codigo)::bigint <= ?", ENV.fetch("MAX_CODE").to_i)
                end

                scope
                  .order(Arel.sql("COALESCE(NULLIF(vista_codigo, ''), codigo)::bigint DESC"))
                  .limit(limit.positive? ? limit : 10)
                  .pluck(Arel.sql("COALESCE(NULLIF(vista_codigo, ''), codigo)"))
              end

    replace_photos = ActiveModel::Type::Boolean.new.cast(ENV.fetch("REPLACE_PHOTOS", "true"))
    replace_documents = ActiveModel::Type::Boolean.new.cast(ENV.fetch("REPLACE_DOCUMENTS", "true"))
    download_files = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DOWNLOAD_FILES", "true"))
    progress_every = [ENV.fetch("PROGRESS_EVERY", "10").to_i, 1].max
    progress_format = ENV.fetch("PROGRESS_FORMAT", "human")
    workers = [ENV.fetch("WORKERS", "1").to_i, 1].max
    started_at = Time.current

    puts "Reconciliação Vista iniciada em #{started_at.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "Total planejado: #{codigos.size} imóveis | workers=#{workers} | dry_run=#{dry_run} | replace_photos=#{replace_photos} | replace_documents=#{replace_documents} | download_files=#{download_files}"

    progress_callback = lambda do |progress|
      should_print = progress[:current] == 1 ||
                     (progress[:current] % progress_every).zero? ||
                     progress[:current] == progress[:total] ||
                     progress.dig(:last, :status) == "failed"
      next unless should_print

      last = progress[:last]
      payload = {
        current: progress[:current],
        total: progress[:total],
        percent: progress[:percent],
        eta: format_duration(progress[:eta_seconds]),
        elapsed: format_duration(progress[:elapsed_seconds]),
        rate_seconds_per_item: progress[:rate_seconds_per_item],
        updated: progress[:updated],
        skipped: progress[:skipped],
        failed: progress[:failed],
        photos_reused: progress[:photos_reused],
        photos_downloaded: progress[:photos_downloaded],
        photos_pending_download: progress[:photos_pending_download],
        documents_reused: progress[:documents_reused],
        documents_downloaded: progress[:documents_downloaded],
        documents_pending_download: progress[:documents_pending_download],
        last_code: last[:codigo],
        last_status: last[:status],
        last_reason: last[:reason],
        last_vista_imo_codigo: last[:vista_imo_codigo],
        last_photos_api: last[:photos_api],
        last_documents_attached: last[:documents_attached],
        last_prontuarios_count: last[:prontuarios_count],
        last_errors: last[:errors].presence
      }

      if progress_format == "json"
        puts payload.to_json
      else
        puts "[#{payload[:current]}/#{payload[:total]} #{payload[:percent]}%] " \
             "ETA #{payload[:eta]} | ok=#{payload[:updated]} skipped=#{payload[:skipped]} failed=#{payload[:failed]} | " \
             "último=#{payload[:last_code]} #{payload[:last_status]}#{payload[:last_reason].present? ? " (#{payload[:last_reason]})" : ""} | " \
             "mídia=#{payload[:last_vista_imo_codigo].presence || '-'} fotos_api=#{payload[:last_photos_api]} docs=#{payload[:last_documents_attached]} pront=#{payload[:last_prontuarios_count]}"
      end
    end

    result = Vista::PropertyReconciliationService.new(
      codigos: codigos,
      dry_run: dry_run,
      replace_photos: replace_photos,
      replace_documents: replace_documents,
      download_files: download_files,
      workers: workers,
      progress_callback: progress_callback
    ).call

    puts({
      dry_run: result.dry_run,
      scanned: result.scanned,
      updated: result.updated,
      skipped: result.skipped,
      failed: result.failed,
      photos_reused: result.photos_reused,
      photos_downloaded: result.photos_downloaded,
      photos_pending_download: result.photos_pending_download,
      photos_detached: result.photos_detached,
      documents_reused: result.documents_reused,
      documents_downloaded: result.documents_downloaded,
      documents_pending_download: result.documents_pending_download,
      documents_detached: result.documents_detached,
      report_path: result.report_path
    }.to_json)

    if result.errors.any?
      puts "Erros:"
      result.errors.each { |row| puts row.to_json }
    end
  end

  def format_duration(seconds)
    return "calculando" if seconds.nil?

    seconds = seconds.to_i
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    rest = seconds % 60

    if hours.positive?
      format("%dh%02dm%02ds", hours, minutes, rest)
    elsif minutes.positive?
      format("%dm%02ds", minutes, rest)
    else
      "#{rest}s"
    end
  end
end

namespace :vista_files do
  desc "Indexa arquivos referenciados no dump raw Vista para controle de download"
  task index: :environment do
    batch_id = ENV["BATCH_ID"].presence
    batch = batch_id ? VistaImportBatch.find(batch_id) : VistaImportBatch.latest_first.first

    result = Vista::FileAssetIndexService.new(
      batch: batch,
      dry_run: ENV.fetch("DRY_RUN", "true"),
      reset: ENV.fetch("RESET", "false")
    ).call

    puts "Vista file assets index"
    puts "  Ambiente: #{Rails.env}"
    puts "  Batch ID: #{result.batch_id}"
    puts "  Dry run: #{result.dry_run}"
    puts "  Registros raw lidos: #{result.scanned}"
    puts "  Arquivos indexados/previstos: #{result.indexed}"
    puts "  Registros sem arquivo: #{result.skipped}"

    result.by_kind.sort.each do |kind, count|
      puts "    #{kind}: #{count}"
    end
  end

  desc "Baixa arquivos Vista pendentes e anexa no ActiveStorage"
  task download: :environment do
    statuses = ENV.fetch("STATUS", "pending").split(",").map(&:strip).reject(&:blank?)
    scope = VistaFileAsset.where(status: statuses)
    scope = scope.where(kind: ENV["KIND"]) if ENV["KIND"].present?
    scope = scope.where(codigo_imovel: ENV["CODIGO"]) if ENV["CODIGO"].present?

    result = Vista::FileAssetDownloadService.new(
      scope: scope,
      dry_run: ENV.fetch("DRY_RUN", "true"),
      limit: ENV["LIMIT"],
      batch_size: ENV.fetch("BATCH_SIZE", Vista::FileAssetDownloadService::DEFAULT_BATCH_SIZE),
      workers: ENV.fetch("WORKERS", Vista::FileAssetDownloadService::DEFAULT_WORKERS)
    ).call

    puts "Vista file assets download"
    puts "  Ambiente: #{Rails.env}"
    puts "  ActiveStorage service: #{Rails.application.config.active_storage.service}"
    puts "  Dry run: #{result.dry_run}"
    puts "  Workers: #{result.workers}"
    puts "  Lidos: #{result.scanned}"
    puts "  Baixados/anexados: #{result.downloaded}"
    puts "  Reaproveitados/anexados: #{result.reused}"
    puts "  Ignorados: #{result.skipped}"
    puts "  Falhas: #{result.failed}"

    if result.errors.any?
      puts "  Erros:"
      result.errors.first(20).each do |error|
        puts "    ##{error[:asset_id]} #{error[:source_url]}: #{error[:error]}"
      end
      puts "    ... #{result.errors.size - 20} erro(s) omitido(s)" if result.errors.size > 20
    end
  end

  desc "Materializa fotos em Habitation.pictures como anexos ActiveStorage, reaproveitando blobs existentes por filename"
  task materialize_api_photos: :environment do
    scope = Vista::ApiPictureMaterializationService.default_scope
    scope = scope.where(codigo: ENV["CODIGO"].to_s.split(",").map(&:strip).reject(&:blank?)) if ENV["CODIGO"].present?
    attached_ids = ActiveStorage::Attachment.where(record_type: "Habitation", name: "photos").select(:record_id)
    scope = scope.where.not(id: attached_ids) if ActiveModel::Type::Boolean.new.cast(ENV.fetch("ONLY_WITHOUT_ATTACHED", "false"))

    result = Vista::ApiPictureMaterializationService.new(
      scope: scope,
      dry_run: ENV.fetch("DRY_RUN", "true"),
      replace: ENV.fetch("REPLACE", "false"),
      limit: ENV["LIMIT"],
      batch_size: ENV.fetch("BATCH_SIZE", Vista::ApiPictureMaterializationService::DEFAULT_BATCH_SIZE),
      workers: ENV.fetch("WORKERS", Vista::ApiPictureMaterializationService::DEFAULT_WORKERS)
    ).call

    puts "Vista API pictures materialization"
    puts "  Ambiente: #{Rails.env}"
    puts "  ActiveStorage service: #{Rails.application.config.active_storage.service}"
    puts "  Dry run: #{result.dry_run}"
    puts "  Replace: #{result.replace}"
    puts "  Workers: #{result.workers}"
    puts "  Imóveis lidos: #{result.properties_scanned}"
    puts "  Fotos avaliadas: #{result.pictures_scanned}"
    puts "  Já anexadas: #{result.already_attached}"
    puts "  Reaproveitadas por filename: #{result.reused}"
    puts "  Baixadas: #{result.downloaded}"
    puts "  Pendentes de download: #{result.pending_download}"
    puts "  Removidas por replace: #{result.detached}"
    puts "  Falhas: #{result.failed}"

    if result.errors.any?
      puts "  Erros:"
      result.errors.first(20).each do |error|
        puts "    #{error[:codigo]} #{error[:url]}: #{error[:error]}"
      end
      puts "    ... #{result.errors.size - 20} erro(s) omitido(s)" if result.errors.size > 20
    end
  end

  desc "Resume arquivos Vista indexados"
  task summary: :environment do
    puts "Vista file assets summary"
    puts "  Total: #{VistaFileAsset.count}"

    VistaFileAsset.group(:kind, :status).order(:kind, :status).count.each do |(kind, status), count|
      puts "    #{kind}/#{status}: #{count}"
    end
  end

  desc "Vincula arquivos Vista indexados aos imóveis importados pelo codigo_imovel"
  task link_habitations: :environment do
    batch_id = ENV["BATCH_ID"].presence
    batch = batch_id ? VistaImportBatch.find(batch_id) : VistaImportBatch.latest_first.first

    result = Vista::FileAssetHabitationLinkService.new(
      batch: batch,
      dry_run: ENV.fetch("DRY_RUN", "true")
    ).call

    puts "Vista file assets habitation link"
    puts "  Ambiente: #{Rails.env}"
    puts "  Batch ID: #{result.batch_id}"
    puts "  Dry run: #{result.dry_run}"
    puts "  Arquivos vinculados/previstos: #{result.linked}"
  end
end

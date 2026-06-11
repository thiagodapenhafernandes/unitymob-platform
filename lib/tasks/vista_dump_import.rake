namespace :vista_dump do
  desc "Importa imoveis e proprietarios ausentes a partir do dump SQL da Vista"
  task import: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true")
    dump_dir = ENV.fetch("DUMP_DIR", Vista::DumpImportService::DEFAULT_DUMP_DIR)
    limit = ENV["LIMIT"]

    result = Vista::DumpImportService.new(dump_dir: dump_dir, dry_run: dry_run, limit: limit).call

    puts "Vista dump import"
    puts "  Ambiente: #{Rails.env}"
    puts "  Dry run: #{result.dry_run}"
    puts "  Imoveis lidos: #{result.scanned_properties}"
    puts "  Imoveis ja existentes: #{result.existing_properties}"
    puts "  Imoveis criados/previstos: #{result.created_properties}"
    puts "  Imoveis com erro: #{result.failed_properties}"
    puts "  Proprietarios ja existentes usados: #{result.existing_proprietors}"
    puts "  Proprietarios criados/previstos: #{result.created_proprietors}"
    puts "  Imoveis criados/previstos com fotos: #{result.properties_with_pictures}"
    puts "  URLs de fotos importadas/previstas: #{result.imported_picture_urls}"

    if result.errors.any?
      puts "  Erros:"
      result.errors.first(20).each do |error|
        puts "    #{error[:codigo]}: #{error[:erro]}"
      end
      puts "    ... #{result.errors.size - 20} erro(s) omitido(s)" if result.errors.size > 20
    end
  end

  desc "Completa dados faltantes dos imoveis ja importados pelo dump Vista"
  task backfill_existing: :environment do
    dry_run = ENV.fetch("DRY_RUN", "true")
    dump_dir = ENV.fetch("DUMP_DIR", Vista::DumpBackfillService::DEFAULT_DUMP_DIR)
    only_imported = ENV.fetch("ONLY_IMPORTED", "true")
    limit = ENV["LIMIT"]

    result = Vista::DumpBackfillService.new(
      dump_dir: dump_dir,
      dry_run: dry_run,
      only_imported: only_imported,
      limit: limit
    ).call

    puts "Vista dump backfill"
    puts "  Ambiente: #{Rails.env}"
    puts "  Dry run: #{result.dry_run}"
    puts "  Apenas importados pelo dump: #{only_imported}"
    puts "  Linhas lidas: #{result.scanned}"
    puts "  Imoveis elegiveis: #{result.eligible}"
    puts "  Imoveis atualizados/previstos: #{result.updated}"
    puts "  Imoveis com erro: #{result.failed}"
    puts "  Enderecos criados/atualizados: #{result.addresses_upserted}"
    puts "  Caracteristicas preenchidas: #{result.characteristics_filled}"
    puts "  Infraestrutura preenchida: #{result.infrastructure_filled}"
    puts "  Portais preenchidos: #{result.portal_flags_filled}"
    puts "  Contatos de proprietario preenchidos: #{result.owner_contacts_filled}"
    puts "  Dados de corretor preenchidos: #{result.broker_fields_filled}"

    if result.errors.any?
      puts "  Erros:"
      result.errors.first(20).each do |error|
        puts "    #{error[:codigo]}: #{error[:erro]}"
      end
      puts "    ... #{result.errors.size - 20} erro(s) omitido(s)" if result.errors.size > 20
    end
  end
end

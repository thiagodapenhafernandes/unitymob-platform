namespace :vista_raw do
  desc "Importa todos os dumps SQL da Vista para uma camada raw auditavel"
  task import: :environment do
    result = Vista::RawDumpImportService.new(
      dump_dir: ENV.fetch("DUMP_DIR", Vista::RawDumpImportService::DEFAULT_DUMP_DIR),
      dry_run: ENV.fetch("DRY_RUN", "true"),
      tables: ENV["TABLES"],
      batch_size: ENV.fetch("BATCH_SIZE", Vista::RawDumpImportService::DEFAULT_BATCH_SIZE),
      truncate: ENV.fetch("TRUNCATE", "false")
    ).call

    puts "Vista raw import"
    puts "  Ambiente: #{Rails.env}"
    puts "  Dump: #{result.dump_dir}"
    puts "  Dry run: #{result.dry_run}"
    puts "  Batch ID: #{result.batch&.id || '-'}"
    puts "  Tabelas lidas: #{result.tables.size}"
    puts "  Linhas lidas: #{result.total_rows}"

    result.tables.each do |table, info|
      puts "    #{table}: #{info[:rows]} linha(s), #{info[:columns]} coluna(s)"
    end

    if result.errors.any?
      puts "  Erros:"
      result.errors.each do |error|
        puts "    #{error[:table]}: #{error[:error]}"
      end
    end
  end

  desc "Resume os registros raw importados da Vista no ultimo batch"
  task summary: :environment do
    batch = VistaImportBatch.latest_first.first

    unless batch
      puts "Nenhum batch Vista raw encontrado."
      next
    end

    puts "Vista raw summary"
    puts "  Batch ID: #{batch.id}"
    puts "  Status: #{batch.status}"
    puts "  Dump: #{batch.dump_dir}"
    puts "  Iniciado em: #{batch.started_at || '-'}"
    puts "  Finalizado em: #{batch.finished_at || '-'}"
    puts "  Total: #{batch.vista_raw_records.count}"

    batch.vista_raw_records.group(:table_name).order(:table_name).count.each do |table, count|
      puts "    #{table}: #{count}"
    end
  end
end

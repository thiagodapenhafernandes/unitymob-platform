namespace :vista_clean do
  desc "Importa cadastros principais Vista para tabelas reais do CRM"
  task import: :environment do
    batch_id = ENV["BATCH_ID"].presence
    batch = batch_id ? VistaImportBatch.find(batch_id) : VistaImportBatch.latest_first.first

    result = Vista::CleanImportService.new(
      batch: batch,
      dry_run: ENV.fetch("DRY_RUN", "true"),
      reset: ENV.fetch("RESET", "false")
    ).call

    puts "Vista clean import"
    puts "  Ambiente: #{Rails.env}"
    puts "  Batch ID: #{result.batch_id}"
    puts "  Dry run: #{result.dry_run}"

    result.stats.sort.each do |key, value|
      puts "  #{key}: #{value}"
    end

    if result.errors.any?
      puts "  Erros:"
      result.errors.first(30).each do |error|
        puts "    #{error[:scope]} #{error[:key]}: #{error[:error]}"
      end
      puts "    ... #{result.errors.size - 30} erro(s) omitido(s)" if result.errors.size > 30
    end
  end
end

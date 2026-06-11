namespace :vista_operational do
  desc "Importa dados operacionais do raw Vista para tabelas reais do CRM"
  task import: :environment do
    batch_id = ENV["BATCH_ID"].presence
    batch = batch_id ? VistaImportBatch.find(batch_id) : VistaImportBatch.latest_first.first

    result = Vista::OperationalImportService.new(
      batch: batch,
      dry_run: ENV.fetch("DRY_RUN", "true"),
      reset: ENV.fetch("RESET", "false"),
      tables: ENV["TABLES"]
    ).call

    puts "Vista operational import"
    puts "  Ambiente: #{Rails.env}"
    puts "  Batch ID: #{result.batch_id}"
    puts "  Dry run: #{result.dry_run}"
    puts "  Linhas lidas: #{result.total_rows}"

    result.tables.each do |table, count|
      puts "    #{table}: #{count}"
    end
  end

  desc "Resume importacao operacional Vista"
  task summary: :environment do
    puts "Vista operational summary"
    puts "  ClientInteraction: #{ClientInteraction.count}"
    puts "  HabitationInteraction: #{HabitationInteraction.count}"
    puts "  CrmAppointment: #{CrmAppointment.count}"
    puts "  ClientPropertyInterest: #{ClientPropertyInterest.count}"
  end
end

namespace :data_hygiene do
  desc "Sanitiza valores duplicados de localização em imóveis e endereços"
  task sanitize_locations: :environment do
    require "csv"

    execute = ENV["EXECUTE"] == "1"
    result = DataHygiene::LocationValueSanitizer.new(execute: execute).call

    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'} data_hygiene:sanitize_locations"
    puts "#{result.groups} grupos | #{result.updates} registros #{execute ? 'atualizados' : 'a atualizar'}"
    puts "log: #{result.log_path}" if result.log_path
  end

  desc "Remove espaços desnecessários de campos textuais mantendo acentos e conteúdo"
  task sanitize_whitespace: :environment do
    execute = ENV["EXECUTE"] == "1"
    result = DataHygiene::WhitespaceSanitizer.new(execute: execute).call

    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'} data_hygiene:sanitize_whitespace"
    puts "#{result.columns} colunas | #{result.updates} valores #{execute ? 'atualizados' : 'a atualizar'}"
    puts "log: #{result.log_path}" if result.log_path
  end
end

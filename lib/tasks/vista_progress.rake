namespace :vista do
  desc "Acompanhar progresso da importacao (UUID gerado pelo thor builder_fields)"
  task :progress, [:progress_id] => :environment do |_, args|
    progress_id = args[:progress_id].to_s

    if progress_id.blank?
      puts "Uso: rake 'vista:progress[UUID]'"
      exit 1
    end

    data = Rails.cache.read("vista:import:#{progress_id}")
    unless data.present?
      puts "Nenhum progresso encontrado para #{progress_id}."
      exit 1
    end

    fetch = lambda do |key|
      data[key] || data[key.to_s] || data[key.to_sym]
    end

    total_pages = fetch.call(:total_pages).to_i
    current_page = fetch.call(:current_page).to_i
    processed = fetch.call(:processed).to_i
    created = fetch.call(:created).to_i
    updated = fetch.call(:updated).to_i
    failed = fetch.call(:failed).to_i
    status = fetch.call(:status) || 'unknown'
    last_codigo = fetch.call(:last_codigo)
    last_error = fetch.call(:last_error)
    started_at = fetch.call(:started_at)
    finished_at = fetch.call(:finished_at)
    updated_at = fetch.call(:updated_at)

    percent = if total_pages > 0
                ((current_page.to_f / total_pages) * 100).round(1)
              else
                0
              end

    puts "Vista import progress: #{progress_id}"
    puts "Status: #{status}"
    puts "Paginas: #{current_page}/#{total_pages} (#{percent}%)"
    puts "Processados: #{processed} | Criados: #{created} | Atualizados: #{updated} | Falhas: #{failed}"
    puts "Ultimo codigo: #{last_codigo}" if last_codigo.present?
    puts "Ultimo erro: #{last_error}" if last_error.present?
    puts "Inicio: #{started_at}" if started_at.present?
    puts "Fim: #{finished_at}" if finished_at.present?
    puts "Atualizado em: #{updated_at}" if updated_at.present?
  end
end

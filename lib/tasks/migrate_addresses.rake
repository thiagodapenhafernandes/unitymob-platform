namespace :data do
  desc "Migrate and standardize addresses from Habitations to Address model"
  task migrate_addresses: :environment do
    puts "Starting address migration..."
    
    total = Habitation.count
    processed = 0
    updated = 0
    errors = 0
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    bar_width = progress_bar_width

    Habitation.find_each do |habitation|
      processed += 1
      
      begin
        address = habitation.address || habitation.build_address
        
        # Avoid overwriting if address already looks complete and new
        # But we want to standardize, so we proceed.
        
        # 1. API Lookup + fallback normalization via service
        enriched = EnrichAddressService.new(
          cep: habitation[:cep],
          fallback: {
            tipo_endereco: habitation[:tipo_endereco],
            logradouro: habitation[:endereco],
            bairro: habitation[:bairro],
            cidade: habitation[:cidade],
            uf: habitation[:uf]
          }
        ).call

        address.tipo_endereco = enriched[:tipo_endereco]
        address.logradouro = enriched[:logradouro]
        address.bairro = enriched[:bairro]
        address.cidade = enriched[:cidade]
        address.uf = enriched[:uf]

        # 2. Critical Data Preservation
        address.cep = habitation[:cep]
        address.numero = habitation[:numero]
        address.complemento = habitation[:complemento]
        address.bairro_comercial = habitation[:bairro_comercial]
        address.imediacoes = normalize_imediacoes(habitation[:imediacoes])
        address.latitude = habitation[:latitude]
        address.longitude = habitation[:longitude]
        address.pais = habitation[:pais].presence || "Brasil"
        
        # Save
        if address.save
          updated += 1
        else
          puts
          puts "  [ERROR] Invalid Address (ID: #{habitation.id}): #{address.errors.full_messages.join(', ')}"
          errors += 1
        end
        
        # Rate limit
        sleep 0.2 if habitation[:cep].present?

      rescue StandardError => e
        puts
        puts "  [CRITICAL] Error (ID: #{habitation.id}): #{e.message}"
        errors += 1
      ensure
        print_progress(processed: processed, total: total, started_at: started_at, bar_width: bar_width)
      end
    end

    puts
    puts "\n\nMigration completed!"
    puts "Total Processed: #{processed}"
    puts "Addresses Updated: #{updated}"
    puts "Errors: #{errors}"
  end

  def normalize_imediacoes(raw_value)
    case raw_value
    when Array
      raw_value
    when String
      raw_value.split(/[,\n;]+/)
    else
      Array(raw_value)
    end
      .map { |item| item.to_s.strip }
      .reject(&:blank?)
      .uniq
  end

  def print_progress(processed:, total:, started_at:, bar_width:)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    rate = elapsed.positive? ? (processed / elapsed) : 0.0
    percent = total.positive? ? (processed.to_f / total) : 1.0
    remaining = [total - processed, 0].max
    eta = rate.positive? ? (remaining / rate) : 0.0

    filled = [(percent * bar_width).round, bar_width].min
    bar = ("#" * filled).ljust(bar_width, "-")

    print format(
      "\r[%<bar>s] [%<processed>d/%<total>d] [%<percent>.2f%%] [%<elapsed>s] [%<eta>s] [%<rate>6.2f/s]",
      bar: bar,
      processed: processed,
      total: total,
      percent: percent * 100,
      elapsed: format_duration(elapsed),
      eta: format_duration(eta),
      rate: rate
    )
  end

  def format_duration(seconds)
    total = seconds.to_i
    mins = total / 60
    secs = total % 60
    format("%02d:%02d", mins, secs)
  end

  def progress_bar_width
    term_width = (ENV["COLUMNS"].presence || 180).to_i
    dynamic_width = term_width - 70
    [[dynamic_width, 30].max, 190].min
  end
end

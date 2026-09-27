namespace :public_maps do
  # O mapa público só aparece com coordenadas. A geocodificação automática
  # (Address#schedule_missing_coordinates) só dispara quando o endereço é
  # criado/alterado, então imóveis antigos ou importados sem lat/long ficam sem
  # mapa. Esta task enfileira o HabitationGeocodeJob para eles — o job é
  # idempotente (pula quem já tem coordenada). Usa o provedor da conta: Google
  # (chave de servidor) ou Leaflet, que geocodifica pelo Nominatim/OpenStreetMap
  # sem custo (mais lento: 1 imóvel a cada 5s). Rua não encontrada vira o
  # centro do bairro, marcado como aproximado (APPROXIMATE=1 tenta de novo).
  #
  #   bin/rails public_maps:geocode_missing                 # só conta (dry run)
  #   bin/rails public_maps:geocode_missing APPLY=1         # enfileira
  #   bin/rails public_maps:geocode_missing TENANT=default APPLY=1
  desc "Geocodifica imóveis publicados sem coordenadas (TENANT=slug, APPLY=1 para enfileirar)"
  task geocode_missing: :environment do
    apply = ENV["APPLY"] == "1"
    tenants = ENV["TENANT"].present? ? Tenant.where(slug: ENV["TENANT"]) : Tenant.all
    abort "Nenhuma conta encontrada para TENANT=#{ENV["TENANT"]}" if tenants.empty?

    tenants.find_each do |tenant|
      setting = GoogleMapsIntegrationSetting.for(tenant)
      unless setting.configured?
        puts "#{tenant.slug}: mapa não configurado, pulando"
        next
      end
      google = setting.provider == "google"

      # APPROXIMATE=1 também refaz os que ficaram só com o centro do bairro
      # (ex.: depois de configurar uma chave Google de servidor).
      missing = tenant.habitations.public_property_listable
        .joins(:address)
        .where("habitations.latitude IS NULL OR habitations.longitude IS NULL")
      missing = if ENV["APPROXIMATE"] == "1"
                  missing.where("addresses.latitude IS NULL OR addresses.coordinates_precision = ?", Address::NEIGHBORHOOD_PRECISION)
                else
                  missing.where(addresses: { latitude: nil })
                end

      count = missing.count
      unless apply
        puts "#{tenant.slug}: #{count} imóveis publicados sem coordenadas (dry run; use APPLY=1)"
        next
      end

      # Google: uma chamada de teste antes de enfileirar. Chave com restrição de
      # referenciador (feita para o mapa no navegador) é recusada no servidor, e
      # os jobs terminariam sem gravar nada.
      if google
        sample = missing.first.address
        probe = Geo::AddressGeocoder.new(address: sample.logradouro, number: sample.numero, neighborhood: sample.bairro,
                                         city: sample.cidade, state: sample.uf, zip_code: sample.cep, api_key: setting.api_key)
        probe.call
      end
      if google && probe.google_status.in?(Geo::AddressGeocoder::GOOGLE_BLOCKING_STATUSES)
        puts "#{tenant.slug}: Google recusou a chave (#{probe.google_status}: #{probe.google_error}). " \
             "Use uma chave de servidor (restrição por IP) com a Geocoding API habilitada. Nada foi enfileirado."
        next
      end

      # Espaça os jobs: Google ~10/s; Nominatim no máximo 1 requisição/s e cada
      # job pode fazer até 4 (3 variações da rua + bairro), então 1 job a cada 5s.
      missing.pluck(:id).each_with_index do |habitation_id, index|
        wait = google ? (index / 10).seconds : (index * 5).seconds
        HabitationGeocodeJob.set(wait: wait).perform_later(habitation_id, tenant_id: tenant.id)
      end
      provider_label = google ? "Google" : "OpenStreetMap"
      puts "#{tenant.slug}: #{count} geocodificações enfileiradas (#{provider_label})"
    end
  end
end

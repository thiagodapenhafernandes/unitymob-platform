namespace :public_maps do
  # O mapa público só aparece com coordenadas. A geocodificação automática
  # (Address#schedule_missing_coordinates) só dispara quando o endereço é
  # criado/alterado, então imóveis antigos ou importados sem lat/long ficam sem
  # mapa. Esta task enfileira o HabitationGeocodeJob para eles — o job é
  # idempotente (pula quem já tem coordenada) e só roda com Google configurado.
  #
  #   bin/rails public_maps:geocode_missing                 # só conta (dry run)
  #   bin/rails public_maps:geocode_missing APPLY=1         # enfileira
  #   bin/rails public_maps:geocode_missing TENANT=salute APPLY=1
  desc "Geocodifica imóveis publicados sem coordenadas (TENANT=slug, APPLY=1 para enfileirar)"
  task geocode_missing: :environment do
    apply = ENV["APPLY"] == "1"
    tenants = ENV["TENANT"].present? ? Tenant.where(slug: ENV["TENANT"]) : Tenant.all
    abort "Nenhuma conta encontrada para TENANT=#{ENV["TENANT"]}" if tenants.empty?

    tenants.find_each do |tenant|
      setting = GoogleMapsIntegrationSetting.for(tenant)
      unless setting.configured? && setting.provider == "google"
        puts "#{tenant.slug}: Google Maps não configurado, pulando"
        next
      end

      missing = tenant.habitations.public_property_listable
        .joins(:address)
        .where(addresses: { latitude: nil })
        .where("habitations.latitude IS NULL OR habitations.longitude IS NULL")

      count = missing.count
      unless apply
        puts "#{tenant.slug}: #{count} imóveis publicados sem coordenadas (dry run; use APPLY=1)"
        next
      end

      # Espaça as chamadas (~10/s) para não esbarrar no limite da Geocoding API.
      missing.pluck(:id).each_with_index do |habitation_id, index|
        HabitationGeocodeJob.set(wait: (index / 10).seconds).perform_later(habitation_id, tenant_id: tenant.id)
      end
      puts "#{tenant.slug}: #{count} geocodificações enfileiradas"
    end
  end
end

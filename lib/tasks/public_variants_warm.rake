# Pré-processa variantes quentes (card/galeria) dos imóveis públicos para o
# primeiro hit não pagar geração sob demanda no proxy. Resolve via
# Storage::PublicCdnImageUrl (enfileira o que falta + aquece o cache de
# existência). Uso:
#   bundle exec rake images:warm_public_variants LIMIT=500 BATCH_SIZE=50
#   TENANT_ID=1 DRY_RUN=true bundle exec rake images:warm_public_variants
namespace :images do
  desc "Pré-processa variantes quentes dos imóveis públicos (card/galeria)"
  task warm_public_variants: :environment do
    limit = ENV.fetch("LIMIT", "500").to_i
    limit = 500 if limit <= 0
    batch_size = ENV.fetch("BATCH_SIZE", "50").to_i
    batch_size = 50 if batch_size <= 0
    dry_run = ENV.fetch("DRY_RUN", "false").to_s.downcase == "true"
    tenant_id = ENV["TENANT_ID"].presence

    transforms = [
      { resize_to_limit: [1200, 900], format: :webp },
      { resize_to_fill: [560, 420], format: :webp },
      { resize_to_fill: [720, 540], format: :webp }
    ]

    scope = Habitation.public_property_listable
    scope = scope.where(tenant_id: tenant_id) if tenant_id

    processed = 0
    warmed = 0
    scope.find_each(batch_size: batch_size) do |habitation|
      break if processed >= limit

      processed += 1
      sources = habitation.public_image_sources.first(3)
      next if sources.empty? || dry_run

      sources.each do |source|
        transforms.each do |transform|
          Storage::PublicCdnImageUrl.resolve(source, **transform)
          warmed += 1
        end
      end
    rescue StandardError => e
      Rails.logger.warn("[warm_public_variants] habitation_id=#{habitation.id} error=#{e.class}: #{e.message}")
    end

    puts "warm_public_variants: #{processed} imóveis, #{warmed} resoluções#{dry_run ? " (dry run)" : ""}"
  end
end

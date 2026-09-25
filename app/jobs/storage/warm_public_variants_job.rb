module Storage
  # Aquece variants das fotos públicas fora do request, para que o render
  # nunca precise enfileirar centenas de TransformVariantJob de uma vez
  # (tempestade vista no log: 319 enqueues numa home fria).
  # Roda por agendamento; idempotente: só enfileira o que ainda não foi
  # processado e marca o blob em cache para não repetir na próxima varredura.
  class WarmPublicVariantsJob < ApplicationJob
    queue_as :media

    # Sets que renderizam acima da dobra (cards + hero). Detalhe/logo
    # aquecem no primeiro acesso (1 foto por vez, custo irrelevante).
    SETS = [
      { resize_to_fill: [720, 540], format: :webp },
      { resize_to_fill: [540, 405], format: :webp },
      { resize_to_fill: [360, 270], format: :webp },
      { resize_to_limit: [1920, 1080], format: :webp },
      { resize_to_limit: [1440, 810], format: :webp },
      { resize_to_limit: [900, 1600], format: :webp },
      { resize_to_limit: [1200, 900], format: :webp },
      { resize_to_limit: [800, 600], format: :webp },
      { resize_to_limit: [480, 360], format: :webp },
      { resize_to_fill: [720, 520], format: :webp },
      { resize_to_limit: [1440, 360] },
      { resize_to_limit: [768, 360] },
      { resize_to_fill: [1400, 820], format: :webp },
      { resize_to_limit: [640, 1138], format: :webp },
      { resize_to_fill: [720, 860], format: :webp },
      { resize_to_fill: [560, 640], format: :webp }
    ].freeze

    MAX_BLOBS = 300
    RECENT_WINDOW = 30.days
    SWEEP_DEDUP_TTL = 20.hours

    def perform
      enqueued = 0
      candidate_blobs.each do |blob|
        next unless blob.variable?
        SETS.each do |transformations|
          variant = blob.variant(**transformations)
          next if variant_processed?(variant)
          next unless sweep_claim(blob.id, transformations)

          Storage::TransformVariantJob.perform_later(blob, transformations)
          enqueued += 1
        end
      end
      Rails.logger.info("[warm_public_variants] enfileirados=#{enqueued}")
      enqueued
    end

    private

    def candidate_blobs
      habitation_ids = Habitation.active
        .where("habitations.updated_at > ?", RECENT_WINDOW.ago)
        .order(updated_at: :desc)
        .limit(MAX_BLOBS)
        .pluck(:id)
      return [] if habitation_ids.empty?

      ActiveStorage::Attachment
        .where(record_type: Habitation.polymorphic_name, record_id: habitation_ids, name: "photos")
        .includes(:blob)
        .order(:record_id, :id)
        .limit(MAX_BLOBS * 3)
        .filter_map(&:blob)
        .uniq(&:id)
        .first(MAX_BLOBS)
    end

    def variant_processed?(variant)
      variant.respond_to?(:processed?, true) && variant.send(:processed?)
    end

    def sweep_claim(blob_id, transformations)
      digest = ActiveStorage::Variation.wrap(transformations).key
      Rails.cache.write("warm-public-variants/#{blob_id}/#{digest}", "1", unless_exist: true, expires_in: SWEEP_DEDUP_TTL)
    end
  end
end

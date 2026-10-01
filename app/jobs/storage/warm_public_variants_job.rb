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
      { resize_to_limit: [640, 1138], format: :webp },
      { resize_to_fill: [720, 860], format: :webp },
      { resize_to_fill: [560, 640], format: :webp },
      # Miniaturas de galeria com aspect_ratio 720/520 (imóvel e empreendimento):
      # o helper calcula a altura por largura e faltavam justamente essas duas
      # combinações — cada foto nova pagava o processamento na hora (visto no
      # log de produção: pedidos de 1.5-3s no redirect do ActiveStorage).
      { resize_to_fill: [360, 260], format: :webp },
      { resize_to_fill: [520, 376], format: :webp },
      # Miniatura do "empreendimento deste imóvel" embutida na página do
      # imóvel (mesmo motivo: pedido comum, fora do set aquecido).
      { resize_to_fill: [640, 480], format: :webp },
      { resize_to_limit: [1920, 1440], format: :webp },
      # Hero do empreendimento (aspect 16:9, breakpoints do srcset responsivo).
      { resize_to_limit: [640, 360], format: :webp },
      { resize_to_limit: [960, 540], format: :webp },
      { resize_to_limit: [1400, 788], format: :webp },
      # Miniatura de galeria do empreendimento no tema luxury.
      { resize_to_limit: [520, 400], format: :webp }
    ].freeze

    MAX_BLOBS = 300
    # Teto de jobs por varredura: o ImageMagick satura a CPU do servidor (web, banco
    # e fila dividem 4 núcleos). Lotes pequenos e frequentes evitam a rajada de
    # ~2.500 jobs que deixou a home em 9 s; o que sobra entra na próxima varredura.
    MAX_ENQUEUE_PER_RUN = 300
    RECENT_WINDOW = 30.days
    SWEEP_DEDUP_TTL = 20.hours

    def perform
      enqueued = 0
      candidate_blobs.each do |blob|
        break if enqueued >= MAX_ENQUEUE_PER_RUN
        next unless blob.variable?
        SETS.each do |transformations|
          break if enqueued >= MAX_ENQUEUE_PER_RUN

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

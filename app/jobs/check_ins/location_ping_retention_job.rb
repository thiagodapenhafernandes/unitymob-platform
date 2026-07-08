# frozen_string_literal: true

module CheckIns
  # Retenção da trilha de GPS dos corretores (LGPD/privacidade).
  #
  # location_pings acumula lat/lng + ip + user_agent + bateria de cada corretor
  # a cada ~90s durante todo o turno; sem expurgo, o histórico minuto-a-minuto
  # de deslocamento de pessoas físicas cresce indefinidamente. Este job apaga os
  # pings mais antigos que RETENTION_PERIOD.
  #
  # Período PADRÃO: 90 dias — ajustável por política do DPO/conta. Espelha a
  # janela já usada por ErrorEventsCleanupJob. Ajuste RETENTION_PERIOD (ou passe
  # `older_than:` ao agendar) se a base legal exigir outro prazo.
  #
  # Observações:
  # - LocationPing NÃO é TenantScoped; a purga é global por recorded_at, o que é
  #   correto para uma política de retenção temporal (independe de tenant).
  # - Usa delete_all em lotes: NÃO dispara callbacks (não há efeito colateral em
  #   LocationPing além do POINT gerado no save) e evita segurar transações/locks
  #   longos numa tabela de alto volume.
  # - No-op tolerante a pré-migration: se a tabela ainda não existe, retorna 0.
  class LocationPingRetentionJob < ApplicationJob
    queue_as :checkin

    RETENTION_PERIOD = 90.days
    BATCH_SIZE = 5_000

    def perform(older_than: RETENTION_PERIOD.ago, batch_size: BATCH_SIZE)
      return 0 unless table_available?

      cutoff = older_than
      deleted = 0

      loop do
        # DELETE ... WHERE id IN (SELECT ... LIMIT n): apaga em lotes pequenos
        # para não travar a tabela num único DELETE gigante.
        batch_ids = LocationPing.where("recorded_at < ?", cutoff)
                                .limit(batch_size)
                                .pluck(:id)
        break if batch_ids.empty?

        deleted += LocationPing.where(id: batch_ids).delete_all
      end

      Rails.logger.info("[LocationPingRetentionJob] deleted=#{deleted} cutoff=#{cutoff.iso8601}") if deleted.positive?
      deleted
    end

    private

    def table_available?
      LocationPing.table_exists?
    rescue StandardError
      false
    end
  end
end

module Vista
  # Backfill em lote: pagina /imoveis/listar pedindo apenas Codigo e
  # CodigoCorretor, resolve AdminUser local via vista_id e preenche
  # habitations.admin_user_id sem baixar detalhes nem fotos.
  #
  # Uso: Vista::BackfillBrokersService.call
  # Status publicado em SyncStatusService(namespace: "brokers_backfill").
  class BackfillBrokersService
    VISTA_KEY  = ENV.fetch('VISTA_KEY')  { 'ea83a702a7669520304be011258289fd' }
    VISTA_HOST = ENV.fetch('VISTA_HOST') { 'http://saluteim20174-rest.vistahost.com.br' }
    PAGE_SIZE  = 50   # Vista API retorna 400 pra quantidades maiores

    def self.call
      new.call
    end

    def initialize
      @status = SyncStatusService.new(namespace: "brokers_backfill")
      @broker_cache = AdminUser.where.not(vista_id: nil).pluck(:vista_id, :id).to_h
    end

    def call
      @status.mark_processing!(message: "Iniciando backfill de corretores em imóveis...", stats: empty_stats)

      page = 1
      total_pages = nil
      processed = 0
      linked = 0
      unchanged = 0
      missing_broker = 0
      not_found_codigo = 0

      loop do
        response = fetch(page)
        if response.nil?
          @status.mark_failed!(message: "Falha ao buscar página #{page} do Vista.",
                               stats: build_stats(processed: processed, linked: linked, unchanged: unchanged,
                                                  missing_broker: missing_broker, not_found_codigo: not_found_codigo,
                                                  page: page, total_pages: total_pages))
          return
        end

        total_pages ||= response['paginas'].to_i
        entries = response.except('total', 'paginas', 'pagina', 'quantidade')
        break if entries.empty?

        entries.each do |_, row|
          next unless row.is_a?(Hash)
          processed += 1

          codigo   = row['Codigo'].to_s.strip
          vista_id = row['CodigoCorretor'].to_s.strip
          next if codigo.empty?

          if vista_id.empty?
            missing_broker += 1
            next
          end

          broker_id = @broker_cache[vista_id]
          unless broker_id
            missing_broker += 1
            next
          end

          # update em lote sem callbacks
          habitation_ids = Habitation.where(codigo: codigo).pluck(:id, :admin_user_id)
          if habitation_ids.empty?
            not_found_codigo += 1
            next
          end

          to_update = habitation_ids.select { |_, current| current != broker_id }.map(&:first)
          if to_update.any?
            Habitation.where(id: to_update).update_all(admin_user_id: broker_id)
            linked += to_update.size
          else
            unchanged += 1
          end
        end

        progress = total_pages.positive? ? ((page.to_f / total_pages) * 100).to_i : 0
        @status.update_progress!(
          progress: progress,
          message: "Página #{page} de #{total_pages} — #{processed} imóveis, #{linked} vinculados",
          stats: build_stats(processed: processed, linked: linked, unchanged: unchanged,
                             missing_broker: missing_broker, not_found_codigo: not_found_codigo,
                             page: page, total_pages: total_pages)
        )

        break if page >= total_pages
        page += 1
      end

      @status.mark_completed!(
        message: "Backfill finalizado — #{linked} imóveis vinculados, #{missing_broker} sem corretor no Vista, #{not_found_codigo} códigos não encontrados localmente",
        stats: build_stats(processed: processed, linked: linked, unchanged: unchanged,
                           missing_broker: missing_broker, not_found_codigo: not_found_codigo,
                           page: page, total_pages: total_pages)
      )
    rescue => e
      @status.mark_failed!(message: "Exceção: #{e.message}", stats: {})
      raise
    end

    private

    def empty_stats
      { processed: 0, linked: 0, unchanged: 0, missing_broker: 0, not_found_codigo: 0, page: 0, total_pages: 0 }
    end

    def build_stats(**attrs)
      empty_stats.merge(attrs)
    end

    def fetch(page)
      query = {
        fields:     ['Codigo', 'CodigoCorretor'],
        paginacao:  { pagina: page, quantidade: PAGE_SIZE }
      }
      url = "#{VISTA_HOST}/imoveis/listar"
      resp = RestClient.get(url, { params: { key: VISTA_KEY, pesquisa: query.to_json, showtotal: 1 }, accept: :json })
      JSON.parse(resp.body)
    rescue => e
      Rails.logger.warn("[Vista Backfill] Falha na página #{page}: #{e.message}")
      nil
    end
  end
end

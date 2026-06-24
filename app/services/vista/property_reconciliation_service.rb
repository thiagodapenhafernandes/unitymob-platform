require "base64"
require "csv"
require "open-uri"
require "rest-client"
require "securerandom"
require "set"

module Vista
  class PropertyReconciliationService
    MAIN_FIELDS = %w[
      Codigo Referencia ImoCodigo ImoPlaca ImoReferenciaExterna CodigoEmpresa CodigoCategoria CodigoAgencia CodigoEmp CodigoEmpreendimento
      TipoEndereco Endereco Numero Complemento Bloco Bairro BairroComercial Cidade UF CEP Pais Imediacoes
      Latitude Longitude GMapsLatitude GMapsLongitude Empreendimento Categoria CategoriaImovel CategoriaMestre CategoriaGrupo
      Status FinalidadeStatus Venda Situacao Ocupacao EstadoConservacaoImovel Topografia
      ValorVenda ValorLocacao ValorCondominio ValorIptu ValorTotalAluguel ValorVendaM2 ValorLocacaoM2
      ValorVendaAnterior ValorLocacaoAnterior ValorPromocional ValorPermutaImovel SaldoDivida Prestacao
      AreaPrivativa AreaTotal AreaTerreno AreaConstruida Dormitorios Suites DemiSuite BanheiroSocialQtd TotalBanheiros
      Vagas Salas QtdVarandas Elevadores AptosAndar AptosEdificio HidroSuite GaragemTipo GaragemNumeroBox AndarDoApto Andares AnoConstrucao Mobiliado SemMobilia Decorado Garden
      DataCadastro DataAtualizacao DataEntrega DataLancamento DataDisponibilizacao TituloSite DescricaoWeb
      DescricaoEmpreendimento TextoAnuncio Observacoes ObsVenda ObsLocacao InformacaoVenda Visita VisitaAcompanhada
      Chave ChaveNaAgencia CaracteristicaUnica Caracteristicas InfraEstrutura AdministradoraCondominio
      ExibirNoSite ExibirNoSiteSalute DestaqueWeb SuperDestaqueWeb FestivalSalute Lancamento Exclusivo TemPlaca ImovelDWV CodigoDWV
      EEmpreendimento
      AceitaFinanciamento AceitaPermuta AceitaPermutaCarro AceitaPermutaOutro AceitaDacao TipoImovelPermuta
      AceitaPermutaTipoVeiculo AnoMinimoVeicPermuta LocalizacaoPermuta QntDormitoriosPermuta QntSuitesPermuta QntGaragensPermuta
      ComissaoCaptador ComissaoCorretor PercentualComissao ValorComissao ValorLivreProprietario
      ComAdministracao SemAdministracao
      Corretor CorretorNome CodigoCorretor Agenciador CaptadorAccountId Proprietario CodigoProprietario
      FotoDestaque FotoDestaquePequena VideoDestaque URLVideo TourVirtual
      Barra BarraNorte BarraSul Centro FrenteMarAvenidaAtlantica QuadraMar VistaFrenteMar
      Construtora PadraoConstrucao Face DimensoesTerreno Matricula Zona ResponsavelReserva ZeladorNome ZeladorTelefone
      InscricaoImobiliaria LinkPodcast RegiaoFoco Fachada
      ChavesNaMaoDestaque ChavesNaMaoPeriodoLocacao ModeloCasaMineira VivaRealPublicationType VivaRealDivulgarEnderecoVivaReal
      ImovelwebTipoPublicacao ImovelwebModelo mostrarMapa LoftPublicationType ZapTipoOferta
    ].freeze

    ASSOCIATION_FIELDS = {
      "proprietarios" => %w[
        Codigo Nome EmailResidencial Celular FonePrincipal FoneComercial FoneResidencial Observacoes Status
        CPFCNPJ RG TipoPessoa DataCadastro
      ],
      "Foto" => %w[
        Codigo ImagemCodigo Foto FotoOriginal FotoPequena Destaque Ordem Data Descricao Tipo Origem ExibirNoSite ExibirSite
      ],
      "FotoEmpreendimento" => %w[
        Codigo Foto FotoPequena Destaque Ordem Data Descricao Tipo ExibirNoSite
      ],
      "Anexo" => %w[
        Codigo CodigoAnexo Descricao Anexo Arquivo ExibirNoSite ExibirSite Data
      ],
      "Video" => %w[
        Codigo Video URLVideo UrlVideo Destaque Tipo Ordem
      ],
      "prontuarios" => %w[
        Codigo Data Hora Assunto Texto Pendente Corretor CodigoCorretor Cliente Status Datainicio ValorProposta
        VeiculoPublicado DataAnuncio Privado PROPOSTA SolicitanteChave Statusdoimóvel
      ]
    }.freeze

    DEFAULT_FIELDS = (MAIN_FIELDS + ASSOCIATION_FIELDS.map { |name, fields| { name => fields } }).freeze

    PHOTO_MARKER = "/vista.imobi/fotos/".freeze
    DOCUMENT_MARKER = "/vista.imobi/documentos/".freeze
    DOCUMENT_BASE_URL = "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/documentos/".freeze
    BACKUP_BASE_URL = "https://backup-crm.loft.com.br/saluteim20174/vista.imobi/".freeze
    API_FILE_ASSET_DUMP_DIR = "api:vista".freeze
    API_PHOTO_TABLE_NAME = "API_FOTO".freeze
    API_DOCUMENT_TABLE_NAME = "API_ANEXO".freeze

    Result = Struct.new(
      :dry_run, :scanned, :updated, :skipped, :failed, :photos_reused, :photos_downloaded,
      :photos_pending_download, :photos_detached, :documents_reused, :documents_downloaded,
      :documents_pending_download, :documents_detached, :report_path, :rows, :errors,
      keyword_init: true
    )

    def initialize(codigos:, dry_run: true, report_path: nil, host: nil, key: nil, replace_photos: false, replace_documents: true, download_files: true, workers: 1, progress_callback: nil)
      @codigos = Array(codigos).map(&:to_s).map(&:strip).reject(&:blank?).uniq
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @host = host.presence || ENV.fetch("VISTA_HOST")
      @key = key.presence || ENV.fetch("VISTA_KEY")
      @report_path = report_path.presence || default_report_path
      @replace_photos = ActiveModel::Type::Boolean.new.cast(replace_photos)
      @replace_documents = ActiveModel::Type::Boolean.new.cast(replace_documents)
      @download_files = ActiveModel::Type::Boolean.new.cast(download_files)
      @workers = normalize_workers(workers)
      @progress_callback = progress_callback
      @api_file_asset_batch_mutex = Mutex.new
    end

    def call
      result = Result.new(
        dry_run: @dry_run,
        scanned: 0,
        updated: 0,
        skipped: 0,
        failed: 0,
        photos_reused: 0,
        photos_downloaded: 0,
        photos_pending_download: 0,
        photos_detached: 0,
        documents_reused: 0,
        documents_downloaded: 0,
        documents_pending_download: 0,
        documents_detached: 0,
        report_path: @report_path,
        rows: [],
        errors: []
      )

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result_mutex = Mutex.new

      if @workers <= 1 || @codigos.size <= 1
        @codigos.each { |codigo| process_codigo(codigo, result, result_mutex, started_at) }
      else
        process_parallel(result, result_mutex, started_at)
      end

      write_report(result)
      result
    end

    private

    def normalize_workers(workers)
      requested = workers.to_i.positive? ? workers.to_i : 1
      [requested, max_workers_for_connection_pool, @codigos.size].compact.min
    end

    def max_workers_for_connection_pool
      [ActiveRecord::Base.connection_pool.size - 1, 1].max
    end

    def process_parallel(result, result_mutex, started_at)
      queue = Queue.new
      @codigos.each { |codigo| queue << codigo }

      @workers.times.map do
        Thread.new do
          loop do
            begin
              codigo = queue.pop(true)
            rescue ThreadError
              break
            end

            begin
              process_codigo(codigo, result, result_mutex, started_at)
            ensure
              ActiveRecord::Base.connection_handler.clear_active_connections!
            end
          end
        end
      end.each(&:join)
    end

    def process_codigo(codigo, result, result_mutex, started_at)
      row = reconcile_codigo(codigo)
      progress_payload = nil

      result_mutex.synchronize do
        result.rows << row
        result.scanned += 1
        result.updated += 1 if row[:status] == "updated"
        result.skipped += 1 if row[:status] == "skipped"
        result.failed += 1 if row[:status] == "failed"
        result.photos_reused += row[:photos_reused].to_i
        result.photos_downloaded += row[:photos_downloaded].to_i
        result.photos_pending_download += row[:photos_pending_download].to_i
        result.photos_detached += row[:photos_detached].to_i
        result.documents_reused += row[:documents_reused].to_i
        result.documents_downloaded += row[:documents_downloaded].to_i
        result.documents_pending_download += row[:documents_pending_download].to_i
        result.documents_detached += row[:documents_detached].to_i
        result.errors << row if row[:status] == "failed"
        progress_payload = build_progress(result, row, result.scanned, @codigos.size, started_at)
      end

      emit_progress(progress_payload)
    end

    def build_progress(result, row, current, total, started_at)
      return unless @progress_callback

      elapsed_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      rate = current.positive? ? elapsed_seconds / current : nil
      remaining = rate ? (total - current) * rate : nil

      {
        current: current,
        total: total,
        percent: total.positive? ? ((current.to_f / total) * 100).round(2) : 100.0,
        elapsed_seconds: elapsed_seconds.round,
        eta_seconds: remaining&.round,
        rate_seconds_per_item: rate&.round(2),
        scanned: result.scanned,
        updated: result.updated,
        skipped: result.skipped,
        failed: result.failed,
        photos_reused: result.photos_reused,
        photos_downloaded: result.photos_downloaded,
        photos_pending_download: result.photos_pending_download,
        documents_reused: result.documents_reused,
        documents_downloaded: result.documents_downloaded,
        documents_pending_download: result.documents_pending_download,
        last: row
      }
    end

    def emit_progress(payload)
      return if payload.blank? || @progress_callback.blank?

      @progress_callback.call(payload)
    end

    def reconcile_codigo(codigo)
      api = fetch_api(codigo)
      photos = photo_rows(api["Foto"])
      development_photos = photo_rows(api["FotoEmpreendimento"])
      documents = document_rows(api["Anexo"])
      media_codes = media_codes_for(api, photos)
      return base_row(codigo).merge(status: "skipped", reason: "api_empty") unless api_has_property_data?(api, photos)

      habitation = find_habitation_for_vista_codigo(codigo) || build_habitation_for_api(codigo, api)
      owner = resolve_proprietor(api)
      broker = resolve_broker(api)
      before = snapshot(habitation)

      counters = Hash.new(0)
      failed_photos = []
      failed_documents = []

      unless @dry_run
        Habitation.transaction do
          update_property!(habitation, api, owner, broker, photos, development_photos)
          update_address!(habitation, api)
          sync_broker_assignment!(habitation, api, broker)
          sync_photos!(habitation, photos, counters, failed_photos)
          sync_documents!(habitation, codigo, media_codes, documents, counters, failed_documents)
          sync_prontuarios!(habitation, api, owner, broker)
        end
      end

      after = @dry_run ? before : snapshot(habitation.reload)
      base_row(codigo).merge(
        status: "updated",
        reason: nil,
        vista_codigo: value(api["Codigo"]),
        vista_imo_codigo: value(api["ImoCodigo"]),
        vista_imo_placa: value(api["ImoPlaca"]),
        vista_referencia_externa: value(api["ImoReferenciaExterna"]),
        media_codes: media_codes.join("|"),
        changed_fields: changed_fields(before, after).join("|"),
        owner_code: api["CodigoProprietario"],
        broker_code: broker&.vista_id || broker_code_from_api(api),
        photos_api: photos.size,
        photos_attached: after[:photos_count],
        photos_reused: counters[:photos_reused],
        photos_downloaded: counters[:photos_downloaded],
        photos_pending_download: counters[:photos_pending_download],
        photos_detached: counters[:photos_detached],
        photos_failed: failed_photos.size,
        documents_codes: document_codes_for(codigo, media_codes).join("|"),
        documents_attached: after[:documents_count],
        documents_reused: counters[:documents_reused],
        documents_downloaded: counters[:documents_downloaded],
        documents_pending_download: counters[:documents_pending_download],
        documents_detached: counters[:documents_detached],
        documents_failed: failed_documents.size,
        prontuarios_count: after[:prontuarios_count],
        errors: (failed_photos + failed_documents).map { |item| "#{item[:source]}: #{item[:error]}" }.join(" | ")
      )
    rescue StandardError => e
      base_row(codigo).merge(status: "failed", reason: e.class.name, errors: e.message)
    end

    def find_habitation_for_vista_codigo(codigo)
      normalized_codigo = codigo.to_s.strip
      return nil if normalized_codigo.blank?

      Habitation.find_by(vista_codigo: normalized_codigo) ||
        Habitation.find_by(codigo: normalized_codigo)
    end

    def build_habitation_for_api(codigo, api)
      Habitation.new(
        codigo: value(api["Codigo"]).presence || codigo.to_s.strip,
        categoria: value(api["Categoria"]).presence || "Apartamento",
        status: Habitation.normalize_status(value(api["Status"])).presence || "Venda",
        skip_auto_audit: true
      )
    end

    def fetch_api(codigo)
      api = {}
      MAIN_FIELDS.each_slice(75) do |fields|
        merge_api!(api, fetch_detail(codigo, fields))
      end

      merge_api!(api, fetch_detail(codigo, [{ "Foto" => ASSOCIATION_FIELDS.fetch("Foto") }]))
      return api unless api_has_property_data?(api, photo_rows(api["Foto"]))

      ASSOCIATION_FIELDS.except("Foto").each do |association, fields|
        merge_api!(api, fetch_detail(codigo, [{ association => fields }]))
      end

      api
    end

    def fetch_detail(codigo, fields)
      response = RestClient.get(
        "#{@host}/imoveis/detalhes",
        params: { key: @key, imovel: codigo, pesquisa: { "fields" => fields }.to_json, showSuspended: 1 },
        accept: :json
      )
      normalize_detail_response(JSON.parse(response.body))
    rescue RestClient::ExceptionWithResponse => e
      association_hash = fields.first if fields.size == 1 && fields.first.is_a?(Hash)
      if association_hash
        association, association_fields = association_hash.first
        association_fields = Array(association_fields)
        if association_fields.size > 1
          midpoint = association_fields.size / 2
          left = fetch_detail(codigo, [{ association => association_fields[0...midpoint] }])
          right = fetch_detail(codigo, [{ association => association_fields[midpoint..] }])
          return merge_api!(left, right)
        end
      end

      return {} if fields.size <= 1

      midpoint = fields.size / 2
      left = fetch_detail(codigo, fields[0...midpoint])
      right = fetch_detail(codigo, fields[midpoint..])
      merge_api!(left, right)
    end

    def normalize_detail_response(parsed)
      case parsed
      when Hash
        parsed
      when Array
        parsed.find { |item| item.is_a?(Hash) } || {}
      else
        {}
      end
    end

    def merge_api!(target, source)
      source.each do |key, source_value|
        next if key.to_s.start_with?("_")

        target[key] = if target[key].is_a?(Hash) && source_value.is_a?(Hash)
                        target[key].merge(source_value)
                      elsif source_value.present? || !target.key?(key)
                        source_value
                      else
                        target[key]
                      end
      end

      target
    end

    def api_has_property_data?(api, photos)
      photos.any? || %w[Endereco Numero CEP Empreendimento TituloSite CodigoProprietario Agenciador CodigoCorretor].any? { |field| api[field].present? }
    end

    def update_property!(habitation, api, owner, broker, photos, development_photos)
      features = normalized_feature_hash(api["Caracteristicas"])
      infrastructure = normalized_infrastructure_list(api["InfraEstrutura"])
      use_development_photos = photos.blank? && development_photos.present? && habitation_type(api) != "Empreendimento"
      pictures = pictures_payload_for_update(habitation, photos)
      development_pictures = preserve_picture_order(habitation.fotos_empreendimento, pictures_payload(development_photos))
      development_code = codigo_empreendimento_from_api(api, habitation)

      attrs = compact_attrs(
        categoria: value(api["Categoria"]),
        tipo: habitation_type(api),
        status: Habitation.normalize_status(value(api["Status"])),
        situacao: value(api["Situacao"]),
        ocupacao_status: value(api["Ocupacao"]),
        tipo_endereco: value(api["TipoEndereco"]),
        endereco: value(api["Endereco"]),
        numero: value(api["Numero"]),
        complemento: value(api["Complemento"]),
        bairro: value(api["Bairro"]),
        bairro_comercial: value(api["BairroComercial"]),
        cidade: value(api["Cidade"]),
        uf: value(api["UF"]).to_s.first(2).presence,
        cep: value(api["CEP"]),
        pais: value(api["Pais"]),
        imediacoes: split_list(api["Imediacoes"]),
        latitude: decimal(api["Latitude"]) || decimal(api["GMapsLatitude"]),
        longitude: decimal(api["Longitude"]) || decimal(api["GMapsLongitude"]),
        codigo_empreendimento: development_code,
        nome_empreendimento: development_name_from_vista(api, development_code),
        titulo_anuncio: value(api["TituloSite"]),
        descricao_web: value(api["DescricaoWeb"]),
        dormitorios_qtd: integer(api["Dormitorios"]),
        suites_qtd: integer(api["Suites"]),
        demi_suites_qtd: integer(api["DemiSuite"]),
        banheiros_qtd: bathrooms_count(api),
        vagas_qtd: integer(api["Vagas"]),
        salas_qtd: integer(api["Salas"]),
        varandas_qtd: integer(api["QtdVarandas"]),
        area_privativa_m2: decimal(api["AreaPrivativa"]),
        area_total_m2: decimal(api["AreaTotal"]),
        valor_venda_cents: money_cents(api["ValorVenda"]),
        valor_locacao_cents: money_cents(api["ValorLocacao"]),
        valor_condominio_cents: money_cents(api["ValorCondominio"]),
        valor_iptu_cents: money_cents(api["ValorIptu"]),
        data_cadastro_crm: datetime(api["DataCadastro"]),
        data_atualizacao_crm: datetime(api["DataAtualizacao"]),
        data_entrega: datetime(api["DataEntrega"]),
        proprietario: value(api["Proprietario"]) || owner&.name,
        proprietario_codigo: value(api["CodigoProprietario"]) || owner&.vista_code,
        proprietor_id: owner&.id,
        codigo_corretor: broker&.vista_id || broker_code_from_api(api),
        admin_user_id: broker&.id,
        agenciador: value(api["AdministradoraCondominio"]),
        pictures: pictures,
        fotos_empreendimento: development_pictures,
        use_development_photos_flag: use_development_photos
      )

      attrs.merge!(
        vista_codigo: value(api["Codigo"]),
        vista_imo_codigo: value(api["ImoCodigo"]),
        vista_imo_placa: value(api["ImoPlaca"]),
        vista_referencia_externa: value(api["ImoReferenciaExterna"]),
        bloco: value(api["Bloco"]),
        status_vista: value(api["Status"]),
        categoria_grupo: value(api["CategoriaGrupo"]),
        area_terreno_m2: decimal(api["AreaTerreno"]),
        area_util_m2: decimal(api["AreaConstruida"]),
        valor_total_aluguel_cents: total_rent_cents(api),
        valor_venda_anterior_cents: money_cents(api["ValorVendaAnterior"]),
        valor_locacao_anterior_cents: money_cents(api["ValorLocacaoAnterior"]),
        valor_por_m2_cents: money_cents(api["ValorVendaM2"]),
        valor_promocional_cents: money_cents(api["ValorPromocional"]),
        saldo_devedor_cents: money_cents(api["SaldoDivida"]),
        numero_prestacoes: integer(api["Prestacao"]),
        banheiro_social_qtd: integer(api["BanheiroSocialQtd"]),
        andar: integer(api["AndarDoApto"]),
        andares_qtd: integer(api["Andares"]),
        aptos_andar: integer(api["AptosAndar"]),
        aptos_edificio: integer(api["AptosEdificio"]),
        elevadores_qtd: integer(api["Elevadores"]),
        hidromassagem_qtd: integer(api["HidroSuite"]),
        ano_construcao: integer(api["AnoConstrucao"]),
        tipo_vaga: value(api["GaragemTipo"]),
        numero_box: value(api["GaragemNumeroBox"]),
        estado_conservacao: estado_conservacao_value(api),
        topografia: value(api["Topografia"]),
        face: value(api["Face"]),
        construtora: value(api["Construtora"]),
        perfil_construcao: value(api["PadraoConstrucao"]),
        dimensoes_terreno: value(api["DimensoesTerreno"]),
        matricula_imovel: value(api["Matricula"]),
        zona: value(api["Zona"]),
        responsavel_reserva: value(api["ResponsavelReserva"]),
        zelador_nome: value(api["ZeladorNome"]),
        zelador_telefone: value(api["ZeladorTelefone"]),
        inscricao_imobiliaria: value(api["InscricaoImobiliaria"]),
        regiao_foco: value(api["RegiaoFoco"]),
        tipo_fachada: value(api["Fachada"]),
        descricao_empreendimento: value(api["DescricaoEmpreendimento"]),
        descricao_interna: value(api["Observacoes"]),
        observacoes: observations_value(api),
        condicoes_negociacao: value(api["InformacaoVenda"]),
        observacoes_visitas: visit_notes(api),
        key_location: key_location(api),
        key_location_notes: value(api["Chave"]),
        exibir_no_site_flag: yes?(api["ExibirNoSite"]) || yes?(api["ExibirNoSiteSalute"]),
        exibir_no_site_salute_flag: yes?(api["ExibirNoSiteSalute"]),
        destaque_web_flag: yes?(api["DestaqueWeb"]),
        festival_salute_flag: yes?(api["SuperDestaqueWeb"]) || yes?(api["FestivalSalute"]),
        lancamento_flag: yes?(api["Lancamento"]),
        exclusivo_flag: yes?(api["Exclusivo"]),
        tem_placa_flag: yes?(api["TemPlaca"]),
        imovel_dwv: value(api["ImovelDWV"]),
        codigo_dwv: unique_dwv_code(api, habitation),
        mobiliado_flag: yes?(api["Mobiliado"]) || feature_selected?(features, "Mobiliado"),
        sem_mobilia_flag: yes?(api["SemMobilia"]) || feature_selected?(features, "Sem mobília"),
        decorado_flag: yes?(api["Decorado"]) || feature_selected?(features, "Decorado"),
        garden_flag: yes?(api["Garden"]) || feature_selected?(features, "Garden"),
        quadra_mar_flag: yes?(api["QuadraMar"]) || feature_selected?(features, "Quadra mar"),
        barra_flag: yes?(api["Barra"]),
        barra_norte_flag: yes?(api["BarraNorte"]),
        barra_sul_flag: yes?(api["BarraSul"]),
        centro_flag: yes?(api["Centro"]),
        frente_mar_avenida_atlantica_flag: yes?(api["FrenteMarAvenidaAtlantica"]),
        vista_frente_mar_flag: yes?(api["VistaFrenteMar"]) || feature_selected?(features, "Vista frente mar"),
        destaque_localizacao: location_highlights(api).index_by(&:itself),
        aceita_financiamento_flag: yes?(api["AceitaFinanciamento"]),
        aceita_permuta_flag: yes?(api["AceitaPermuta"]),
        aceita_permuta_veiculo_flag: yes?(api["AceitaPermutaCarro"]),
        aceita_permuta_outros_flag: yes?(api["AceitaPermutaOutro"]),
        aceita_permuta_imovel_flag: value(api["TipoImovelPermuta"]).present?,
        aceita_doacao_flag: yes?(api["AceitaDacao"]),
        tipo_veiculo_aceito_permuta: value(api["AceitaPermutaTipoVeiculo"]),
        ano_minimo_veiculo_aceito_permuta: integer(api["AnoMinimoVeicPermuta"]),
        permuta_localizacao: value(api["LocalizacaoPermuta"]),
        permuta_dormitorios_qtd: integer(api["QntDormitoriosPermuta"]),
        permuta_suites_qtd: integer(api["QntSuitesPermuta"]),
        permuta_garagens_qtd: integer(api["QntGaragensPermuta"]),
        permuta_valor_cents: money_cents(api["ValorPermutaImovel"]),
        valor_aceito_permuta_cents: money_cents(api["ValorPermutaImovel"]),
        captador_commission_percentage: commission_percentage(api["ComissaoCaptador"], api["PercentualComissao"]),
        broker_commission_percentage: decimal(api["ComissaoCorretor"]),
        valor_comissao_cents: commission_amount_cents(api),
        valor_livre_proprietario_cents: money_cents(api["ValorLivreProprietario"]),
        salute_rental_management_flag: rental_management_flag(api),
        captador_account_id: value(api["CaptadorAccountId"]),
        tour_virtual: value(api["TourVirtual"]),
        podcast_url: value(api["LinkPodcast"]),
        videos: videos_payload(api),
        publicar_zapimoveis: value(api["ZapTipoOferta"]).present?,
        publicar_viva_real_vrsync: value(api["VivaRealPublicationType"]).present?,
        publicar_imovelweb: value(api["ImovelwebTipoPublicacao"]).present? || value(api["ImovelwebModelo"]).present?,
        publicar_loft: value(api["LoftPublicationType"]).present?,
        publicar_casa_mineira: value(api["ModeloCasaMineira"]).present?,
        publicar_chaves_na_mao: chaves_na_mao_publication(api),
        destaque_chaves_na_mao: chaves_na_mao_destaque(api),
        periodo_locacao_chaves_na_mao: chaves_na_mao_period(api),
        modelo_casa_mineira: normalized_option_value(api["ModeloCasaMineira"]),
        tipo_publicacao_viva_real: normalized_option_value(api["VivaRealPublicationType"]),
        divulgar_endereco_viva_real: normalized_option_value(api["VivaRealDivulgarEnderecoVivaReal"]),
        tipo_publicacao_imovelweb: normalized_option_value(api["ImovelwebTipoPublicacao"]),
        mostrar_mapa_imovelweb: normalized_option_value(api["mostrarMapa"]),
        piscina_flag: feature_selected?(features, "Piscina") || infrastructure_selected?(infrastructure, "Piscina coletiva") || infrastructure_selected?(infrastructure, "Piscina aquecida") || infrastructure_selected?(infrastructure, "Piscina infantil"),
        lavabo_flag: feature_selected?(features, "Lavabo"),
        caracteristicas: features,
        infra_estrutura: infrastructure,
        caracteristica_unica: split_list(api["CaracteristicaUnica"]),
        foto_classificacao: photo_classification(api, photos),
        vista_payload: api
      )

      attrs = compact_attrs(attrs).merge(clearable_property_attrs(api))
      habitation.assign_attributes(attrs)
      habitation.save!
      ensure_attribute_options!(features.keys, infrastructure)
    end

    def update_address!(habitation, api)
      address = habitation.address || habitation.build_address
      address.assign_attributes(
        compact_attrs(
          tipo_endereco: value(api["TipoEndereco"]),
          logradouro: value(api["Endereco"]),
          numero: value(api["Numero"]),
          complemento: value(api["Complemento"]),
          bairro: value(api["Bairro"]),
          bairro_comercial: value(api["BairroComercial"]),
          cidade: value(api["Cidade"]),
          uf: value(api["UF"]).to_s.first(2).presence,
          cep: value(api["CEP"]),
          pais: value(api["Pais"]),
          imediacoes: split_list(api["Imediacoes"]),
          latitude: decimal(api["Latitude"]) || decimal(api["GMapsLatitude"]),
          longitude: decimal(api["Longitude"]) || decimal(api["GMapsLongitude"])
        ).merge(clearable_address_attrs(api))
      )
      address.save!
    end

    def sync_prontuarios!(habitation, api, owner, broker)
      prontuario_rows(api["prontuarios"]).each do |row|
        code = value(row["Codigo"])
        next if code.blank?

        interaction = HabitationInteraction.find_or_initialize_by(
          source_table: "VISTA_API_PRONTUARIO",
          source_key: "#{habitation.codigo}:#{code}"
        )
        agent_code = value(row["CodigoCorretor"])
        interaction.assign_attributes(
          habitation: habitation,
          proprietor: owner,
          admin_user: AdminUser.find_by(vista_id: agent_code) || broker,
          vista_habitation_code: habitation.codigo,
          vista_client_code: value(row["Cliente"]),
          vista_agent_code: agent_code,
          subject: value(row["Assunto"]),
          body: value(row["Texto"]),
          occurred_at: datetime_from_date_time(row["Data"], row["Hora"]),
          started_at: datetime(row["Datainicio"]),
          pending: yes?(row["Pendente"]),
          private: yes?(row["Privado"]),
          proposal: yes?(row["PROPOSTA"]),
          status: value(row["Status"]) || value(row["Statusdoimóvel"]),
          advertised: value(row["Anunciado"]),
          published_vehicle: value(row["VeiculoPublicado"]),
          key_requester: value(row["SolicitanteChave"]),
          proposal_value_cents: money_cents(row["ValorProposta"]),
          metadata: row
        )
        interaction.save!
      end
    end

    def sync_photos!(habitation, photos, counters, failures)
      protected_attachment_ids = photos_attachment_scope(habitation).pluck(:id)
      ordered_attachment_ids = []

      photos.each_with_index do |photo, index|
        url = photo["Foto"].to_s
        next if url.blank?

        source_path = source_path_from_url(url)
        asset = upsert_photo_asset!(habitation, photo, url, source_path, index)

        blob = asset_blob(asset)
        restored_blob = false
        if blob && !blob_exists?(blob)
          blob = restore_missing_blob_from_url(blob, url, asset.filename, counters, failures)
          restored_blob = blob.present?
        end
        reused_blob = false
        if blob
          counters[:photos_reused] += 1 unless restored_blob
          reused_blob = true
        elsif !@download_files
          counters[:photos_pending_download] += 1
          next
        else
          begin
            blob = create_blob_from_url(url, asset.filename, nil, service_name: StorageIntegrationSetting.current.photo_service_name)
            counters[:photos_downloaded] += 1
          rescue StandardError => e
            failures << { source: url, error: e.message }
            mark_photo_asset_failed!(asset, e)
            next
          end
        end

        attachment = attach_blob_once!(habitation, "photos", blob)
        ordered_attachment_ids << attachment.id
        mark_photo_asset_attached!(asset, attachment, reused: reused_blob)
      end

      ordered_attachment_ids = preserve_attachment_order(habitation, ordered_attachment_ids.uniq)
      final_attachment_ids = merge_protected_attachment_order(habitation, protected_attachment_ids, ordered_attachment_ids)

      if @replace_photos
        stale = if final_attachment_ids.any?
                  photos_attachment_scope(habitation).where.not(id: final_attachment_ids)
                else
                  photos_attachment_scope(habitation)
                end

        counters[:photos_detached] += stale.count
        stale.destroy_all
        habitation.update!(photo_ids_order: final_attachment_ids)
      end

      habitation.update!(photo_ids_order: final_attachment_ids) if final_attachment_ids.any? && !@replace_photos
    end

    def api_file_asset_batch
      return @api_file_asset_batch if @api_file_asset_batch

      @api_file_asset_batch_mutex.synchronize do
        @api_file_asset_batch ||= VistaImportBatch.where(dump_dir: API_FILE_ASSET_DUMP_DIR).latest_first.first ||
          VistaImportBatch.create!(dump_dir: API_FILE_ASSET_DUMP_DIR, status: "completed")
      end
    end

    def upsert_photo_asset!(habitation, photo, url, source_path, index)
      source_path = normalized_photo_source_path(habitation, url, source_path)
      asset = VistaFileAsset.find_or_initialize_by(
        vista_import_batch: api_file_asset_batch,
        table_name: API_PHOTO_TABLE_NAME,
        source_path: source_path
      )
      asset.assign_attributes(
        habitation: habitation,
        kind: "property_photo",
        status: asset.status.presence || "pending",
        codigo_imovel: habitation.codigo,
        source_url: url,
        filename: File.basename(source_path),
        active_storage_name: "photos",
        position: integer(photo["Ordem"]) || index + 1,
        metadata: asset.metadata.to_h.merge("api" => photo)
      )
      asset.save!
      asset
    end

    def normalized_photo_source_path(habitation, url, source_path)
      path = source_path.presence || parsed_url_path(url)
      return path if path.present?

      filename = File.basename(url.to_s.split("?").first)
      filename = "foto-#{SecureRandom.hex(8)}" if filename.blank? || filename == "."
      ["api", "property_photo", habitation.codigo.presence || habitation.id, filename].join("/")
    end

    def parsed_url_path(url)
      URI.parse(url.to_s).path.to_s.delete_prefix("/")
    rescue URI::InvalidURIError
      nil
    end

    def mark_photo_asset_attached!(asset, attachment, reused:)
      blob = attachment.blob
      asset.update!(
        status: "downloaded",
        active_storage_attachment: attachment,
        active_storage_key: blob.key,
        storage_checksum: blob.checksum,
        storage_byte_size: blob.byte_size,
        storage_content_type: blob.content_type,
        storage_service_name: blob.service_name,
        downloaded_at: Time.current,
        reused_at: reused ? Time.current : asset.reused_at,
        error_message: nil
      )
    end

    def mark_photo_asset_failed!(asset, error)
      asset.update!(
        status: "failed",
        attempts: asset.attempts + 1,
        error_message: error.message
      )
    end

    def photos_attachment_scope(habitation)
      ActiveStorage::Attachment.where(record: habitation, name: "photos")
    end

    def sync_documents!(habitation, codigo, media_codes, documents, counters, failures)
      expected_attachment_ids = []
      documents.each_with_index { |document, index| upsert_document_asset!(habitation, document, index) }

      VistaFileAsset
        .where(kind: "property_document", codigo_imovel: document_codes_for(codigo, media_codes))
        .order(:codigo_imovel, :id)
        .find_each do |asset|
          begin
            if !@download_files && document_download_pending?(asset, habitation)
              counters[:documents_pending_download] += 1
              next
            end

            status, attachment = attach_document_asset!(asset, habitation)
            expected_attachment_ids << attachment.id if attachment
            counters[:documents_reused] += 1 if status == :reused
            counters[:documents_downloaded] += 1 if status == :downloaded
          rescue StandardError => e
            failures << { source: asset.source_path, error: e.message }
          end
        end

      if @replace_documents
        stale = ActiveStorage::Attachment.where(record: habitation, name: "autorizacoes_venda")
        stale = stale.where.not(id: expected_attachment_ids.uniq) if expected_attachment_ids.any?
        counters[:documents_detached] += stale.count
        stale.destroy_all
      end
    end

    def upsert_document_asset!(habitation, document, index)
      source_url = document_source_url(document)
      source_path = normalized_document_source_path(habitation, document, source_url)
      filename = document_filename(document, source_path, source_url)
      return if source_url.blank? || source_path.blank? || filename.blank?

      asset = VistaFileAsset.find_or_initialize_by(
        vista_import_batch: api_file_asset_batch,
        table_name: API_DOCUMENT_TABLE_NAME,
        source_path: source_path
      )
      asset.assign_attributes(
        habitation: habitation,
        kind: "property_document",
        status: asset.status.presence || "pending",
        codigo_imovel: habitation.codigo,
        source_url: source_url,
        filename: filename,
        active_storage_name: "autorizacoes_venda",
        position: integer(document["Ordem"]) || index + 1,
        metadata: asset.metadata.to_h.merge("api" => document)
      )
      asset.save!
    end

    def document_source_url(document)
      raw = value(document["Arquivo"]) || value(document["Anexo"]) || value(document["URL"]) || value(document["Url"]) || value(document["Link"])
      return if raw.blank?
      return raw if raw.match?(%r{\Ahttps?://}i)

      URI.join(DOCUMENT_BASE_URL, raw).to_s
    rescue URI::InvalidURIError
      nil
    end

    def normalized_document_source_path(habitation, document, source_url)
      raw = value(document["Arquivo"]) || value(document["Anexo"]) || value(document["NomeArquivo"])
      path = if raw.to_s.match?(%r{\Ahttps?://}i)
               source_path_from_url(raw, marker: DOCUMENT_MARKER)
             else
               raw
             end
      path = source_path_from_url(source_url, marker: DOCUMENT_MARKER) if path.blank? || path.match?(%r{\Ahttps?://}i)
      return path if path.present?

      filename = document_filename(document, nil, source_url)
      ["api", "property_document", habitation.codigo.presence || habitation.id, filename].join("/")
    end

    def document_filename(document, source_path, source_url)
      value(document["NomeArquivo"]).presence ||
        value(document["Anexo"]).presence ||
        value(document["Descricao"]).presence ||
        safe_basename(source_path) ||
        safe_basename(URI.parse(source_url.to_s).path)
    rescue URI::InvalidURIError
      safe_basename(source_url.to_s.split("?").first)
    end

    def safe_basename(value)
      filename = File.basename(value.to_s)
      filename.presence unless filename == "."
    end

    def document_download_pending?(asset, habitation)
      attachment_name = asset.active_storage_name.presence || "autorizacoes_venda"
      asset_blob(asset).blank? && existing_attachment_by_filename(habitation, attachment_name, asset.filename).blank?
    end

    def attach_document_asset!(asset, habitation)
      attachment_name = asset.active_storage_name.presence || "autorizacoes_venda"
      existing = existing_attachment_by_filename(habitation, attachment_name, asset.filename)
      if existing
        mark_document_asset_attached!(asset, existing, source_url: asset.source_url, reused: true)
        return [:reused, existing]
      end

      blob = asset_blob(asset)
      status = :reused

      unless blob
        blob = create_blob_from_url(asset.source_url, asset.filename, asset.storage_content_type, service_name: StorageIntegrationSetting.current.document_service_name)
        status = :downloaded
      end
    rescue StandardError
      fallback_url = backup_url_for(asset)
      raise if fallback_url.blank?

      blob = create_blob_from_url(fallback_url, asset.filename, asset.storage_content_type, service_name: StorageIntegrationSetting.current.document_service_name)
      status = :downloaded
    ensure
      if blob
        attachment = attach_blob_once!(habitation, attachment_name, blob)
        mark_document_asset_attached!(asset, attachment, source_url: fallback_url.presence || asset.source_url, reused: status == :reused)
      end

      return [status, attachment] if blob
    end

    def mark_document_asset_attached!(asset, attachment, source_url:, reused:)
      blob = attachment.blob
      asset.update!(
        status: "downloaded",
        source_url: source_url,
        active_storage_attachment: attachment,
        active_storage_key: blob.key,
        storage_checksum: blob.checksum,
        storage_byte_size: blob.byte_size,
        storage_content_type: blob.content_type,
        storage_service_name: blob.service_name,
        attempts: asset.attempts + 1,
        downloaded_at: Time.current,
        reused_at: reused ? Time.current : asset.reused_at,
        error_message: nil,
        metadata: asset.metadata.to_h.merge("reconciled_to_codigo" => asset.habitation&.codigo)
      )
    end

    def document_codes_for(codigo, media_codes)
      codes = Array(media_codes) + [codigo]
      codes.map(&:to_s).reject(&:blank?).uniq
    end

    def asset_blob(asset)
      return unless asset

      if asset.active_storage_attachment_id.present?
        blob = ActiveStorage::Attachment.find_by(id: asset.active_storage_attachment_id)&.blob
        return blob if blob
      end

      if asset.active_storage_key.present?
        blob = ActiveStorage::Blob.find_by(key: asset.active_storage_key)
        return blob if blob
      end

      return unless asset.kind == "property_photo" && asset.filename.present?

      ActiveStorage::Blob
        .joins(:attachments)
        .where(active_storage_attachments: { record_type: "Habitation", name: "photos" })
        .where(filename: asset.filename)
        .order(:id)
        .first
    end

    def attach_blob_once!(record, name, blob)
      existing = ActiveStorage::Attachment.find_by(record: record, name: name, blob: blob)
      if existing
        Storage::PublicPropertyPhoto.publish_attachment!(existing)
        return existing
      end

      record.public_send(name).attach(blob)
      attachment = ActiveStorage::Attachment.find_by!(record: record, name: name, blob: blob)
      Storage::PublicPropertyPhoto.publish_attachment!(attachment)
      attachment
    end

    def existing_attachment_by_filename(record, name, filename)
      ActiveStorage::Attachment
        .where(record: record, name: name)
        .joins(:blob)
        .find_by(active_storage_blobs: { filename: filename })
    end

    def create_blob_from_url(url, filename, content_type, service_name:)
      Storage::ActiveStorageRegistry.fetch!(service_name) unless service_name.to_sym == :local
      io = URI.open(url)
      ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: filename,
        content_type: io.content_type.presence || content_type.presence || Marcel::MimeType.for(name: filename),
        service_name: service_name
      )
    end

    def blob_exists?(blob)
      blob.service.exist?(blob.key)
    rescue StandardError
      false
    end

    def restore_missing_blob_from_url(blob, url, filename, counters, failures)
      URI.open(url, read_timeout: 30, open_timeout: 10) do |io|
        blob.service.upload(blob.key, io, checksum: blob.checksum, content_type: blob.content_type)
      end
      counters[:photos_downloaded] += 1
      blob
    rescue StandardError => e
      failures << { source: url, error: "restore_missing_blob #{filename}: #{e.message}" }
      nil
    end

    def resolve_proprietor(api)
      code = value(api["CodigoProprietario"])
      return if code.blank?

      proprietor = Proprietor.find_by(vista_code: code)
      attrs = proprietor_attrs(api, code)
      if proprietor
        proprietor.update!(attrs.compact_blank)
        return proprietor
      end

      Proprietor.create!(attrs.merge(vista_code: code, name: attrs[:name].presence || "Proprietário #{code}"))
    end

    def owner_data(api)
      data = api["proprietarios"]
      data.is_a?(Hash) ? data.values.first : Array(data).first
    end

    def proprietor_attrs(api, code)
      data = owner_data(api).is_a?(Hash) ? owner_data(api) : {}
      {
        name: value(api["Proprietario"]) || value(data["Nome"]) || "Proprietário #{code}",
        email: value(data["EmailResidencial"]) || value(data["EmailComercial"]),
        phone_primary: value(data["FonePrincipal"]),
        mobile_phone: value(data["Celular"]) || value(data["CelularConjuge"]) || value(data["FonePrincipal"]),
        business_phone: value(data["FoneComercial"]),
        residential_phone: value(data["FoneResidencial"]),
        cpf_cnpj: value(data["CPFCNPJ"]),
        rg_ie: value(data["RG"]),
        issuing_authority: value(data["RGEmissor"]),
        birth_date: date(data["DataNascimento"]) || date(data["Nascimento"]),
        nationality: value(data["Nacionalidade"]),
        profession: value(data["Profissao"]),
        marital_status: value(data["EstadoCivil"]),
        notes: value(data["Observacoes"]) || value(data["ObservacoesProp"]),
        registered_at: date(data["DataCadastro"]),
        address_type: value(data["EnderecoTipo"]),
        street: value(data["EnderecoResidencial"]) || value(data["EnderecoComercial"]),
        number: value(data["EnderecoNumero"]),
        complement: value(data["EnderecoComplemento"]),
        block: value(data["Bloco"]),
        neighborhood: value(data["BairroResidencial"]) || value(data["BairroComercial"]),
        city: value(data["CidadeResidencial"]) || value(data["CidadeComercial"]),
        uf: value(data["UFResidencial"]) || value(data["UFComercial"]),
        cep: value(data["CEPResidencial"]) || value(data["CEPComercial"]),
        spouse_name: value(data["NomeConjuge"]),
        spouse_email: value(data["EmailConjuge"]),
        spouse_phone: value(data["CelularConjuge"]),
        spouse_cpf_cnpj: value(data["CPFConjuge"])
      }
    end

    def resolve_broker(api)
      code = broker_code_from_api(api)
      return if code.blank?

      AdminUser.find_by(vista_id: code)
    end

    def broker_code_from_api(api)
      value(api["CodigoCorretor"]) || value(api["Agenciador"])
    end

    def media_codes_for(api, photos)
      [
        value(api["ImoCodigo"]),
        *photos.filter_map do |photo|
          value(photo["Codigo"]) || source_path_from_url(photo["Foto"]).to_s.split("/").first.presence
        end
      ].compact_blank.uniq.presence || [value(api["Codigo"])].compact_blank
    end

    def pictures_payload(photos)
      photos.map.with_index do |photo, index|
        {
          "url" => photo["Foto"],
          "url_original" => photo["FotoOriginal"],
          "url_pequena" => photo["FotoPequena"],
          "principal" => yes?(photo["Destaque"]),
          "exibir_no_site" => yes?(photo["ExibirNoSite"]) || yes?(photo["ExibirSite"]),
          "ordem" => integer(photo["Ordem"]) || index + 1,
          "imagem_codigo" => value(photo["ImagemCodigo"]),
          "codigo_midia_vista" => value(photo["Codigo"]),
          "origem" => value(photo["Origem"]),
          "descricao" => value(photo["Descricao"])
        }
      end
    end

    def pictures_payload_for_update(habitation, photos)
      current_pictures = habitation.pictures
      return current_pictures if photos_attachment_scope(habitation).exists? && current_pictures.is_a?(Array)

      preserve_picture_order(current_pictures, pictures_payload(photos))
    end

    def preserve_picture_order(current_pictures, incoming_pictures)
      return incoming_pictures unless current_pictures.is_a?(Array) && current_pictures.any?
      return incoming_pictures if incoming_pictures.blank?

      incoming_by_key = incoming_pictures.index_by { |picture| picture_identity_key(picture) }
      ordered = current_pictures.filter_map { |picture| incoming_by_key.delete(picture_identity_key(picture)) }
      ordered + incoming_by_key.values
    end

    def picture_identity_key(picture)
      return picture.to_s if picture.is_a?(String)
      return "" unless picture.is_a?(Hash)

      value(picture["codigo_midia_vista"]) ||
        value(picture["imagem_codigo"]) ||
        source_path_from_url(picture["url"].presence || picture["Foto"].presence).presence ||
        value(picture["url"]) ||
        value(picture["Foto"])
    end

    def preserve_attachment_order(habitation, incoming_attachment_ids)
      return incoming_attachment_ids if incoming_attachment_ids.blank?

      current_order = Array(habitation.photo_ids_order).map(&:to_i)
      return incoming_attachment_ids if current_order.blank?

      incoming_set = incoming_attachment_ids.to_set
      preserved = current_order.select { |id| incoming_set.include?(id) }
      return incoming_attachment_ids if preserved.blank?

      preserved + incoming_attachment_ids.reject { |id| preserved.include?(id) }
    end

    def merge_protected_attachment_order(habitation, protected_attachment_ids, incoming_attachment_ids)
      protected_attachment_ids = Array(protected_attachment_ids).map(&:to_i).reject(&:zero?)
      incoming_attachment_ids = Array(incoming_attachment_ids).map(&:to_i).reject(&:zero?)
      return incoming_attachment_ids if protected_attachment_ids.blank?

      current_order = Array(habitation.photo_ids_order).map(&:to_i)
      protected_order = current_order.select { |id| protected_attachment_ids.include?(id) }
      protected_order += protected_attachment_ids.reject { |id| protected_order.include?(id) }
      (protected_order + incoming_attachment_ids).uniq
    end

    def photo_rows(raw)
      rows = raw.is_a?(Hash) ? raw.values : Array(raw)
      rows.select { |row| row.is_a?(Hash) && row["Foto"].present? }
        .sort_by { |row| integer(row["Ordem"]) || 999_999 }
    end

    def document_rows(raw)
      rows = raw.is_a?(Hash) ? raw.values : Array(raw)
      rows.select { |row| row.is_a?(Hash) && (row["Arquivo"].present? || row["Anexo"].present? || row["NomeArquivo"].present?) }
        .sort_by { |row| [integer(row["Ordem"]) || 999_999, value(row["Data"]).to_s, value(row["Codigo"]).to_s] }
    end

    def prontuario_rows(raw)
      rows = raw.is_a?(Hash) ? raw.values : Array(raw)
      rows.select { |row| row.is_a?(Hash) }
        .sort_by { |row| [value(row["Data"]).to_s, value(row["Hora"]).to_s, value(row["Codigo"]).to_s] }
    end

    def videos_payload(api)
      urls = [value(api["VideoDestaque"]), value(api["URLVideo"]), value(api["TourVirtual"])]
      raw = api["Video"].is_a?(Hash) ? api["Video"].values : Array(api["Video"])
      urls.concat(raw.filter_map { |row| row.is_a?(Hash) ? value(row["Video"]) || value(row["URLVideo"]) || value(row["UrlVideo"]) : nil })
      urls.compact_blank.uniq
    end

    def normalized_feature_hash(raw)
      normalized_yes_labels(raw, category: "feature").index_by(&:itself)
    end

    def normalized_infrastructure_list(raw)
      normalized_yes_labels(raw, category: "infrastructure")
    end

    def normalized_yes_labels(raw, category:)
      return [] unless raw.is_a?(Hash)

      raw.filter_map do |(key, raw_value)|
        next unless yes?(raw_value)

        AttributeOptions::HabitationFeatureNormalizer.label(key, category: category)
      end.compact_blank.uniq
    end

    def feature_selected?(features, label)
      selected?(features.keys, label, category: "feature")
    end

    def infrastructure_selected?(infrastructure, label)
      selected?(infrastructure, label, category: "infrastructure")
    end

    def selected?(items, label, category:)
      normalized_label = AttributeOptions::HabitationFeatureNormalizer.label(label, category: category)
      normalized_key = AttributeOptions::HabitationFeatureNormalizer.key(normalized_label)
      Array(items).any? { |item| AttributeOptions::HabitationFeatureNormalizer.key(item) == normalized_key }
    end

    def ensure_attribute_options!(features, infrastructure)
      [["feature", features], ["infrastructure", infrastructure]].each do |category, values|
        Array(values).each do |name|
          next if name.blank?

          option = AttributeOption
                   .where(context: "habitation", category: category)
                   .where("lower(name) = ?", name.to_s.downcase)
                   .first
          option ? option.update!(name: name) : AttributeOption.create!(context: "habitation", category: category, name: name)
        rescue ActiveRecord::RecordNotUnique
          retry
        end
      end
      Rails.cache.delete("admin/habitations/form_options/v1")
    end

    def photo_classification(api, photos)
      return "Profissionais" if yes?(api["Profissionais"]) || yes?(api["PROFISSIONAIS"])
      return "Boas" if yes?(api["Boas"]) || yes?(api["BOAS"])
      return "Aceitáveis" if yes?(api["Aceitaveis"]) || yes?(api["ACEITAVEIS"])
      return "Não tem fotos" if photos.blank? && (yes?(api["NaoTemFotos"]) || yes?(api["NAO_TEM_FOTOS"]))

      dump_photo_classification(api, photos)
    end

    def dump_photo_classification(api, photos)
      media_codes_for(api, photos).each do |code|
        row = VistaRawRecord.where(table_name: %w[CADIMO CSDSIM2], codigo_imovel: code).order(id: :desc).pick(:payload)
        next unless row.is_a?(Hash)

        return "Profissionais" if yes?(row["PROFISSIONAIS"])
        return "Boas" if yes?(row["BOAS"])
        return "Aceitáveis" if yes?(row["ACEITAVEIS"])
        return "Não tem fotos" if photos.blank? && yes?(row["NAO_TEM_FOTOS"])
      end

      photos.any? ? nil : "Não tem fotos"
    end

    def sync_broker_assignment!(habitation, api, broker)
      return unless broker

      HabitationBrokerAssignment.where(habitation: habitation, role: HabitationBrokerAssignment.roles[:captador])
                                .where.not(admin_user_id: broker.id)
                                .destroy_all

      assignment = HabitationBrokerAssignment.find_or_initialize_by(
        habitation: habitation,
        vista_source_key: "VISTA_API:#{habitation.codigo}:#{broker.vista_id}:captador"
      )
      assignment.assign_attributes(
        admin_user: broker,
        role: :captador,
        commission_type: :percentage,
        commission_value: decimal(api["ComissaoCaptador"]) || decimal(api["PercentualComissao"]),
        sale_commission_percentage: decimal(api["ComissaoCaptador"]) || decimal(api["PercentualComissao"]),
        rental_commission_percentage: decimal(api["ComissaoCorretor"]),
        observations: "Atualizado pela API Vista",
        vista_payload: {
          "Codigo" => value(api["Codigo"]),
          "Agenciador" => value(api["Agenciador"]),
          "CodigoCorretor" => value(api["CodigoCorretor"]),
          "CorretorNome" => value(api["CorretorNome"])
        }
      )
      assignment.save!
    end

    def key_location(api)
      raw = value(api["Chave"])
      return "Imobiliária" if yes?(api["ChaveNaAgencia"])
      return "Corretor(a)" if raw.to_s.downcase.include?("corret")
      return "Proprietário" if raw.to_s.downcase.include?("propriet")

      raw.present? ? "Outro" : nil
    end

    def habitation_type(api)
      return "Empreendimento" if yes?(api["EEmpreendimento"])
      return "Empreendimento" if value(api["TipoImovel"]).to_s.casecmp("E").zero?
      return "Empreendimento" if value(api["Categoria"]).to_s.casecmp("Empreendimento").zero?

      "Unitário"
    end

    def codigo_empreendimento_from_api(api, habitation)
      return if habitation_type(api) == "Empreendimento"

      code = value(api["CodigoEmpreendimento"]) || value(api["CodigoEmp"])
      return if code.blank? || code == value(api["Codigo"])

      Habitation.empreendimentos.exists?(codigo: code) ? code : nil
    end

    def development_name_from_vista(api, development_code)
      raw_name = value(api["Empreendimento"])
      return if raw_name.blank?
      return raw_name if development_code.present?
      return if Habitation.standalone_category_without_development_name?(value(api["Categoria"]))

      raw_name
    end

    def location_highlights(api)
      {
        "3Avenida" => "3ª Avenida",
        "Aririba" => "Ariribá",
        "AvenidaBrasil" => "Avenida Brasil",
        "BairroFazendaItajai" => "Bairro Fazenda Itajaí",
        "BalnearioPicarras" => "Balneário Piçarras",
        "Barra" => "Barra",
        "BarraNorte" => "Barra Norte",
        "BarraSul" => "Barra Sul",
        "Cabecudas" => "Cabeçudas",
        "Camboriu" => "Camboriú",
        "Centro" => "Centro",
        "Estaleirinho" => "Estaleirinho",
        "Estaleiro" => "Estaleiro",
        "FrenteMarAvenidaAtlantica" => "Frente mar Avenida Atlântica",
        "Itajai" => "Itajaí",
        "Itapema" => "Itapema",
        "MeiaPraia" => "Meia Praia",
        "Morretes" => "Morretes",
        "Nacoes" => "Nações",
        "Pereque" => "Perequê",
        "Pioneiros" => "Pioneiros",
        "PortoBelo" => "Porto Belo",
        "PraiaBrava" => "Praia Brava",
        "PraiaDosAmores" => "Praia dos Amores"
      }.filter_map { |field, label| label if yes?(api[field]) }.uniq
    end

    def split_list(raw)
      value(raw).to_s.split(/[,\n;]+/).map(&:strip).reject(&:blank?).uniq
    end

    def observations_value(api)
      [value(api["ObsVenda"]), value(api["ObsLocacao"]), value(api["InformacaoVenda"]), value(api["TextoAnuncio"])].compact.join("\n\n").presence
    end

    def commission_percentage(primary_raw, fallback_raw = nil)
      primary = decimal(primary_raw)
      fallback = decimal(fallback_raw)
      return primary if primary&.positive?
      return fallback if fallback&.positive?

      primary || fallback
    end

    def commission_amount_cents(api)
      structured_amount = money_cents(api["ValorComissao"])
      return structured_amount if structured_amount.to_i.positive?

      amount_from_notes(api, /valor\s+da\s+comiss[aã]o\??\s*:?\s*([\d.,]+)/i)
    end

    def rental_management_flag(api)
      return true if yes?(api["ComAdministracao"])
      return false if yes?(api["SemAdministracao"])

      boolean_from_notes(api, /tem\s+administra[cç][aã]o\??\s*:?\s*(sim|s|nao|não|n)/i)
    end

    def amount_from_notes(api, pattern)
      note_texts(api).each do |text|
        match = text.match(pattern)
        next unless match

        cents = money_cents(match[1])
        return cents if cents.to_i.positive?
      end

      nil
    end

    def boolean_from_notes(api, pattern)
      note_texts(api).each do |text|
        normalized = I18n.transliterate(text)
        match = normalized.match(pattern)
        next unless match

        return %w[sim s].include?(match[1].to_s.downcase)
      end

      nil
    end

    def note_texts(api)
      %w[ObsVenda ObsLocacao Observacoes InformacaoVenda TextoAnuncio DescricaoWeb].filter_map { |field| value(api[field]) }
    end

    def visit_notes(api)
      visit = value(api["Visita"])
      return visit if visit.present?

      yes?(api["VisitaAcompanhada"]) ? "Visita acompanhada" : nil
    end

    def estado_conservacao_value(api)
      raw = value(api["EstadoConservacaoImovel"])
      return if raw.blank?

      {
        "otimo" => "Ótimo",
        "ótimo" => "Ótimo"
      }.fetch(I18n.transliterate(raw).downcase, raw)
    end

    def clearable_property_attrs(api)
      {
        pais: clearable_value(api, "Pais"),
        complemento: clearable_value(api, "Complemento"),
        codigo_empreendimento: clearable_development_code(api),
        nome_empreendimento: clearable_development_name(api),
        titulo_anuncio: clearable_value(api, "TituloSite"),
        agenciador: clearable_value(api, "AdministradoraCondominio"),
        data_entrega: clearable_datetime(api, "DataEntrega"),
        andar: clearable_integer(api, "AndarDoApto"),
        numero_box: clearable_value(api, "GaragemNumeroBox"),
        estado_conservacao: api.key?("EstadoConservacaoImovel") ? estado_conservacao_value(api) : :__not_available__,
        topografia: clearable_value(api, "Topografia"),
        face: clearable_value(api, "Face"),
        construtora: clearable_value(api, "Construtora"),
        perfil_construcao: clearable_value(api, "PadraoConstrucao"),
        dimensoes_terreno: clearable_value(api, "DimensoesTerreno"),
        matricula_imovel: clearable_value(api, "Matricula"),
        zona: clearable_value(api, "Zona"),
        responsavel_reserva: clearable_value(api, "ResponsavelReserva"),
        zelador_nome: clearable_value(api, "ZeladorNome"),
        zelador_telefone: clearable_value(api, "ZeladorTelefone"),
        inscricao_imobiliaria: clearable_value(api, "InscricaoImobiliaria"),
        regiao_foco: clearable_value(api, "RegiaoFoco"),
        tipo_fachada: clearable_value(api, "Fachada"),
        descricao_empreendimento: clearable_value(api, "DescricaoEmpreendimento"),
        descricao_interna: clearable_value(api, "Observacoes"),
        condicoes_negociacao: clearable_value(api, "InformacaoVenda"),
        observacoes_visitas: api.key?("Visita") || api.key?("VisitaAcompanhada") ? visit_notes(api) : :__not_available__,
        tipo_veiculo_aceito_permuta: clearable_value(api, "AceitaPermutaTipoVeiculo"),
        ano_minimo_veiculo_aceito_permuta: clearable_integer(api, "AnoMinimoVeicPermuta"),
        permuta_localizacao: clearable_value(api, "LocalizacaoPermuta"),
        permuta_dormitorios_qtd: clearable_integer(api, "QntDormitoriosPermuta"),
        permuta_suites_qtd: clearable_integer(api, "QntSuitesPermuta"),
        permuta_garagens_qtd: clearable_integer(api, "QntGaragensPermuta"),
        captador_account_id: clearable_value(api, "CaptadorAccountId"),
        tour_virtual: clearable_value(api, "TourVirtual"),
        podcast_url: clearable_value(api, "LinkPodcast")
      }.reject { |_key, attr_value| attr_value == :__not_available__ }
    end

    def clearable_address_attrs(api)
      {
        pais: clearable_value(api, "Pais"),
        complemento: clearable_value(api, "Complemento")
      }.reject { |_key, attr_value| attr_value == :__not_available__ }
    end

    def clearable_value(api, field)
      return :__not_available__ unless api.key?(field)

      value(api[field])
    end

    def clearable_development_name(api)
      return :__not_available__ unless api.key?("Empreendimento")

      code = value(api["CodigoEmpreendimento"]) || value(api["CodigoEmp"])
      valid_code = code.present? && code != value(api["Codigo"]) && Habitation.empreendimentos.exists?(codigo: code)
      development_name_from_vista(api, valid_code ? code : nil)
    end

    def clearable_development_code(api)
      return :__not_available__ unless api.key?("CodigoEmpreendimento") || api.key?("CodigoEmp")

      codigo_empreendimento_from_api(api, nil)
    end

    def clearable_integer(api, field)
      return :__not_available__ unless api.key?(field)

      integer(api[field])
    end

    def clearable_datetime(api, field)
      return :__not_available__ unless api.key?(field)

      datetime(api[field])
    end

    def normalized_option_value(raw)
      text = value(raw)
      return if text.blank?

      I18n.transliterate(text).downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").presence
    end

    def chaves_na_mao_destaque(api)
      return "sim" if yes?(api["ChavesNaMaoDestaque"])
      return "nao" if value(api["ChavesNaMaoDestaque"]).present?

      nil
    end

    def chaves_na_mao_publication(api)
      yes?(api["ChavesNaMaoDestaque"]) || value(api["ChavesNaMaoPeriodoLocacao"]).present?
    end

    def chaves_na_mao_period(api)
      normalized = normalized_option_value(api["ChavesNaMaoPeriodoLocacao"])
      return if normalized.blank?

      normalized.tr("-", "_")
    end

    def unique_dwv_code(api, habitation)
      code = value(api["CodigoDWV"])
      return if code.blank? || code == "0"

      duplicate = Habitation.where(codigo_dwv: code).where.not(id: habitation.id).exists?
      duplicate ? nil : code
    end

    def source_path_from_url(url, marker: PHOTO_MARKER)
      uri = URI.parse(url.to_s)
      path = uri.path.to_s
      return path.split(marker, 2).last if path.include?(marker)

      path.delete_prefix("/").presence || File.basename(url.to_s)
    rescue URI::InvalidURIError
      File.basename(url.to_s)
    end

    def backup_url_for(asset)
      query = backup_query
      return if query.blank?

      folder = case asset.kind
               when "property_document" then "documentos"
               when "property_photo" then "fotos"
               when "agent_document" then "usuarios"
               when "client_document" then "clientes"
               else "documentos"
               end

      "#{BACKUP_BASE_URL}#{folder}/#{asset.source_path}#{query}"
    end

    def backup_query
      @backup_query ||= begin
        readme_path = Rails.root.join("crm-saluteim20174-20174-2026-05-27-09-53-30", "README.txt")
        File.exist?(readme_path) ? File.read(readme_path)[/\?Policy=.*Key-Pair-Id=[^\s]+/] : nil
      end
    end

    def snapshot(habitation)
      {
        endereco: habitation.endereco,
        numero: habitation.numero,
        complemento: habitation.complemento,
        cep: habitation.cep,
        bairro: habitation.bairro,
        bairro_comercial: habitation.bairro_comercial,
        cidade: habitation.cidade,
        uf: habitation.uf,
        nome_empreendimento: habitation.nome_empreendimento,
        categoria: habitation.categoria,
        status: habitation.status,
        situacao: habitation.situacao,
        ocupacao_status: habitation.ocupacao_status,
        valor_venda_cents: habitation.valor_venda_cents,
        valor_locacao_cents: habitation.valor_locacao_cents,
        valor_condominio_cents: habitation.valor_condominio_cents,
        valor_iptu_cents: habitation.valor_iptu_cents,
        area_privativa_m2: habitation.area_privativa_m2,
        area_total_m2: habitation.area_total_m2,
        dormitorios_qtd: habitation.dormitorios_qtd,
        suites_qtd: habitation.suites_qtd,
        demi_suites_qtd: habitation.demi_suites_qtd,
        banheiros_qtd: habitation.banheiros_qtd,
        vagas_qtd: habitation.vagas_qtd,
        proprietario_codigo: habitation.proprietario_codigo,
        proprietor_id: habitation.proprietor_id,
        codigo_corretor: habitation.codigo_corretor,
        admin_user_id: habitation.admin_user_id,
        vista_imo_codigo: habitation.vista_imo_codigo,
        vista_imo_placa: habitation.vista_imo_placa,
        vista_referencia_externa: habitation.vista_referencia_externa,
        photos_count: habitation.photos.count,
        documents_count: habitation.autorizacoes_venda.count,
        prontuarios_count: habitation.habitation_interactions.where(source_table: "VISTA_API_PRONTUARIO").count
      }
    end

    def changed_fields(before, after)
      before.keys.select { |key| before[key].to_s != after[key].to_s }
    end

    def base_row(codigo)
      {
        codigo: codigo,
        status: nil,
        reason: nil,
        vista_codigo: nil,
        vista_imo_codigo: nil,
        vista_imo_placa: nil,
        vista_referencia_externa: nil,
        media_codes: nil,
        changed_fields: nil,
        owner_code: nil,
        broker_code: nil,
        photos_api: 0,
        photos_attached: 0,
        photos_reused: 0,
        photos_downloaded: 0,
        photos_detached: 0,
        photos_failed: 0,
        documents_codes: nil,
        documents_attached: 0,
        documents_reused: 0,
        documents_downloaded: 0,
        documents_detached: 0,
        documents_failed: 0,
        prontuarios_count: 0,
        errors: nil
      }
    end

    def write_report(result)
      FileUtils.mkdir_p(File.dirname(@report_path))
      headers = result.rows.flat_map(&:keys).uniq
      CSV.open(@report_path, "w", write_headers: true, headers: headers) do |csv|
        result.rows.each { |row| csv << headers.map { |header| row[header] } }
      end
    end

    def default_report_path
      Rails.root.join("tmp", "reports", "vista_property_reconciliation_#{Time.current.strftime('%Y%m%d%H%M%S')}.csv").to_s
    end

    def compact_attrs(attrs)
      attrs.reject { |_key, attr_value| attr_value.nil? }
    end

    def value(raw)
      return if raw.nil?

      normalized = Vista::TextEncodingNormalizer.normalize(raw.to_s).strip
      normalized.presence unless normalized == "NULL" || normalized == "\\N"
    end

    def integer(raw)
      raw_value = value(raw)
      raw_value.present? ? raw_value.to_i : nil
    end

    def bathrooms_count(api)
      integer(api["BanheiroSocialQtd"]) || integer(api["TotalBanheiros"])
    end

    def total_rent_cents(api)
      money_cents(api["ValorLocacao"])
    end

    def decimal(raw)
      raw_value = value(raw)
      return if raw_value.blank?

      BigDecimal(raw_value.tr(",", "."))
    rescue ArgumentError
      nil
    end

    def money_cents(raw)
      amount = decimal(raw)
      amount ? (amount * 100).round.to_i : nil
    end

    def date(raw)
      raw_value = value(raw)
      return if raw_value.blank? || raw_value == "0000-00-00"

      Date.parse(raw_value)
    rescue ArgumentError
      nil
    end

    def datetime(raw)
      raw_value = value(raw)
      return if raw_value.blank? || raw_value == "0000-00-00"

      Time.zone.parse(raw_value)
    rescue StandardError
      nil
    end

    def datetime_from_date_time(date_raw, time_raw)
      date_value = value(date_raw)
      return if date_value.blank? || date_value == "0000-00-00"

      time_value = value(time_raw).presence || "00:00:00"
      Time.zone.parse("#{date_value} #{time_value}")
    rescue StandardError
      datetime(date_raw)
    end

    def yes?(raw)
      text = value(raw).to_s.strip.downcase
      %w[sim s yes y true 1].include?(text)
    end
  end
end

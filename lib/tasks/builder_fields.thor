# lib/tasks/builder_fields.thor
require File.expand_path('config/environment.rb')
require 'rest-client'
require 'thor'
require 'cgi'
require 'uri'
require 'securerandom'
require 'set'

class BuilderFields < Thor::Group
  class_option :strict, type: :boolean, default: false,
               desc: "Quando true, respeita validacoes do model. Por padrao ignora validacoes."
  class_option :progress_id, type: :string, default: nil,
               desc: "UUID para acompanhar com rake 'vista:progress[UUID]'."
  class_option :progress, type: :boolean, default: false,
               desc: "Exibe progresso no console e gera UUID automaticamente."
  class_option :force, type: :boolean, default: false,
               desc: "Compatibilidade com o comando usado no v2."
  class_option :concurrency, type: :numeric, default: 6,
               desc: "Concorrencia para buscar detalhes por pagina (default: 6)."

  desc "building fields from Vista API"

  VISTA_KEY  = ENV.fetch('VISTA_KEY')  { 'ea83a702a7669520304be011258289fd' }
  VISTA_HOST = ENV.fetch('VISTA_HOST') { 'http://saluteim20174-rest.vistahost.com.br' }

  LISTAR_PATH   = '/imoveis/listar'
  DETALHES_PATH = '/imoveis/detalhes'

  HEADERS = { accept: 'application/json' }.freeze
  TIMEOUT = 20
  MAX_RETRIES = 4
  PROGRESS_TTL = 6.hours

  def initialize(args = [], options = {}, config = {})
    super
    opts = self.options || {}
    @progress_enabled = opts[:progress] || opts[:progress_id].present? || ENV['VISTA_PROGRESS_ID'].present?
    @progress_id = opts[:progress_id].presence || ENV['VISTA_PROGRESS_ID'] || SecureRandom.uuid
    @stats = { total: 0, created: 0, updated: 0, failed: 0 }
    @progress_state = {}
    @strict_mode = opts[:strict].to_s == 'true'
    @concurrency = [[opts[:concurrency].to_i, 1].max, 20].min
    @constructor_cache = {}
    @constructor_id_by_canonical = Constructor.pluck(:id, :name).each_with_object({}) do |(id, name), memo|
      memo[canonical_name(name)] = id
    end
    @admin_user_id_by_vista_id = AdminUser.where.not(vista_id: [nil, ""]).pluck(:vista_id, :id).to_h
  end


  def pre_cleanup
    count = Habitation.where(imovel_dwv: 'Sim').delete_all
    say_status :info, "Removidos #{count} imoveis com imovel_dwv='Sim' (para reimportar).", :yellow
  end

  def export
    start_progress! if @progress_enabled

    pagina = 1
    total_importados = 0
    total_paginas = nil

    loop do
      listing = fetch_list(pagina)
      break unless listing.present?

      total_paginas ||= listing['paginas'].to_i
      total_paginas = 1 if total_paginas.zero?
      total_records = listing['total'].to_i
      update_progress(
        total_pages: total_paginas,
        current_page: pagina,
        total_records: total_records.positive? ? total_records : @progress_state[:total_records]
      ) if @progress_enabled

      itens = listing.except('total', 'paginas', 'pagina', 'quantidade').values
      page_size = itens.size

      say_status :info, "Pagina #{pagina}/#{total_paginas} - registros: #{page_size}", :blue
      update_progress(current_page_size: page_size) if @progress_enabled

      batch_attrs = []
      batch_codes = []
      batch_address_by_code = {}

      codigos = itens.map { |item| item['Codigo'].to_s }.reject(&:blank?)
      details_by_codigo = fetch_details_batch(codigos)

      itens.each do |item|
        codigo = item['Codigo'].to_s
        next if codigo.blank?
        begin
          details = details_by_codigo[codigo]
          next unless details

          attrs = build_params(item, details)
          address_attrs = attrs.delete(:_address_attrs)
          batch_attrs << attrs
          batch_codes << attrs[:codigo]
          batch_address_by_code[attrs[:codigo]] = address_attrs if address_attrs.present?

          total_importados += 1
          @stats[:total] += 1

          if @progress_enabled
            update_progress(
              processed: total_importados,
              failed: @stats[:failed],
              last_codigo: codigo
            )
            emit_progress_line
          end
        rescue => e
          @stats[:failed] += 1
          if @progress_enabled
            update_progress(last_error: "#{e.class}: #{e.message}", last_codigo: codigo, failed: @stats[:failed])
            emit_progress_line
          end

          location = e.backtrace&.first.to_s
          method   = location.split("`").last&.gsub("'", "")
          say_status :error,
            "Erro processando codigo #{codigo}: #{e.class} - #{e.message} (em #{method} @ #{location})",
            :red
        end
      end

      if @strict_mode
        batch_attrs.each do |attrs|
          address_attrs = batch_address_by_code[attrs[:codigo]]
          result = upsert_habitation(attrs)
          @stats[result] += 1 if result
          rec = Habitation.find_by(codigo: attrs[:codigo])
          upsert_address_for_habitation(rec, address_attrs) if rec.present? && address_attrs.present?
        end
      elsif batch_attrs.any?
        existing = Habitation.where(codigo: batch_codes).pluck(:codigo).to_set
        sanitized_batch_attrs = sanitize_dwv_link_conflicts(batch_attrs)
        normalized_batch_attrs = sanitized_batch_attrs.map { |attrs| normalize_array_aware_attrs(attrs) }
        Habitation.upsert_all(normalized_batch_attrs, unique_by: :index_habitations_on_codigo, record_timestamps: true)
        sync_addresses_for_codes(batch_address_by_code)

        created = batch_codes.size - existing.size
        updated = existing.size
        @stats[:created] += created
        @stats[:updated] += updated
      end

      if @progress_enabled
        update_progress(
          created: @stats[:created],
          updated: @stats[:updated],
          failed: @stats[:failed]
        )
        emit_progress_line
      end

      break if pagina >= total_paginas
      pagina += 1
    end

    finish_progress!(total_importados) if @progress_enabled
    Habitations::HierarchyNormalizerService.new.call
    created_options = AttributeOptions::RebuildFromUsageService.new.call
    say_status :info, "Attribute options sincronizados: +#{created_options}", :blue
    audit = Habitations::HierarchyAuditService.new(strict: false).call
    say_status :info, "Hierarchy audit: #{audit[:metrics].inspect}", :blue
    say_status :success, "Finalizado! Registros processados: #{total_importados}", :green
    RefreshFeaturedPropertiesJob.perform_later if defined?(RefreshFeaturedPropertiesJob)
  rescue => e
    update_progress(status: 'failed', last_error: "#{e.class}: #{e.message}") if @progress_enabled
    puts "CRASH ERRO: #{e.class} - #{e.message}"
    puts e.backtrace
    raise
  end

  no_tasks do
    def canonical_name(text)
      return "" if text.blank?
      n = I18n.transliterate(text.to_s)
      n = n.upcase.gsub(/[^A-Z0-9]/, ' ')
      
      # Mapeamento manual de casos complexos ou erros do CRM (identificados via Web)
      n = n.gsub(/\bARKKA\b/, 'ARRKA')
      n = n.gsub(/\bBENVEART\b/, 'BENVEARTT')
      n = n.gsub(/\bBENVINHART\b/, 'BENVEARTT')
      n = n.gsub(/\bHAACK\b/, 'HAACKE')
      n = n.gsub(/\bHACKEE\b/, 'HAACKE')
      n = n.gsub(/\bSILVA PARKER\b/, 'SILVA PACKER')
      n = n.gsub(/\bASR RAMOS\b/, 'AS RAMOS')
      n = n.gsub(/\bCEQUINEL\b/, 'CECHINEL')
      n = n.gsub(/\bJ A RUSSI\b/, 'JA RUSSI')
      n = n.gsub(/\bJ A  RUSSI\b/, 'JA RUSSI')

      suffixes = [
        "CONSTRUTORA", "INCORPORADORA", "EMPREENDIMENTO", "EMPREENDIMENTOS", 
        "CONSTRUCAO", "CONTRUTORA", "LTDA", "ENGENHARIA", "S A", "SA", 
        "EIRELI", "ME", "CIA", "GRUPO", "GROUP", "RESIDENCE", "RESIDENCIAL",
        "CONCEPT", "BOUTIQUE", "APPARTAMENTI", " E ", " & "
      ]
      
      suffixes.sort_by { |s| -s.length }.each do |s|
        n = n.gsub(/\b#{s}\b/, '')
      end
      
      n.strip.gsub(/\s+/, '')
    end

    def resolve_constructor(name)
      return nil if name.blank?
      c_name = name.strip
      c_canonical = canonical_name(c_name)
      
      @constructor_cache[c_canonical] ||= begin
        cached_id = @constructor_id_by_canonical[c_canonical]
        if cached_id.present?
          cached_id
        else
          c = Constructor.create!(name: c_name)
          @constructor_id_by_canonical[c_canonical] = c.id
          c.id
        end
      end
    rescue => e
      nil
    end


    def normalize_cep(v)
      s = v&.to_s&.gsub(/\D/, '')
      return nil if s.blank?
      s.length == 8 ? "#{s[0..4]}-#{s[5..7]}" : nil
    end

    def normalize_array_aware_attrs(attrs)
      normalized = attrs.dup

      normalized[:caracteristicas] = normalize_array_column_value(
        normalized[:caracteristicas],
        column: Habitation.columns_hash["caracteristicas"]
      )
      normalized[:infra_estrutura] = normalize_array_column_value(
        normalized[:infra_estrutura],
        column: Habitation.columns_hash["infra_estrutura"]
      )
      normalized[:caracteristica_unica] = normalize_array_column_value(
        normalized[:caracteristica_unica],
        column: Habitation.columns_hash["caracteristica_unica"]
      )

      normalized
    end

    def normalize_array_column_value(value, column:)
      return value unless column&.array

      parsed = parse_as_array(value)
      return parsed if parsed.is_a?(Array)

      value
    end

    def sanitize_dwv_link_conflicts(attrs_list)
      return attrs_list if attrs_list.blank?

      sanitized = attrs_list.map(&:dup)
      dwv_candidates = sanitized.filter_map do |attrs|
        dwv_code = attrs[:codigo_dwv].to_s.strip
        next if dwv_code.blank?
        next unless attrs[:imovel_dwv].to_s.strip.casecmp("Sim").zero?

        [attrs[:codigo].to_s, dwv_code]
      end
      return sanitized if dwv_candidates.blank?

      links_by_dwv = Hash.new { |hash, key| hash[key] = [] }
      dwv_candidates.each { |codigo, dwv_code| links_by_dwv[dwv_code] << codigo }

      existing_map = Habitation
        .where(imovel_dwv: "Sim", codigo_dwv: links_by_dwv.keys)
        .where.not(codigo_dwv: [nil, ""])
        .pluck(:codigo_dwv, :codigo)
        .to_h

      sanitized.each do |attrs|
        codigo = attrs[:codigo].to_s
        dwv_code = attrs[:codigo_dwv].to_s.strip
        next if dwv_code.blank?
        next unless attrs[:imovel_dwv].to_s.strip.casecmp("Sim").zero?

        # Evita colisão com vínculo já existente em outro imóvel.
        existing_codigo = existing_map[dwv_code].to_s
        if existing_codigo.present? && existing_codigo != codigo
          attrs[:codigo_dwv] = nil
          attrs[:imovel_dwv] = "Não"
          next
        end

        # Evita múltiplos imóveis do mesmo batch com o mesmo vínculo DWV.
        duplicated_in_batch = links_by_dwv[dwv_code].uniq
        if duplicated_in_batch.size > 1 && duplicated_in_batch.first != codigo
          attrs[:codigo_dwv] = nil
          attrs[:imovel_dwv] = "Não"
        end
      end

      sanitized
    end

    def parse_as_array(value)
      return nil if value.nil?
      return value if value.is_a?(Array)
      return value.keys if value.is_a?(Hash)

      raw = value.to_s.strip
      return [] if raw.blank?

      if raw.start_with?('[') && raw.end_with?(']')
        begin
          parsed = JSON.parse(raw)
          return parsed if parsed.is_a?(Array)
        rescue JSON::ParserError
          # keep raw split behavior below
        end
      end

      raw
        .to_s
        .strip
        .split(/[,;|]/)
        .map!(&:strip)
        .reject(&:blank?)
    end

    def upsert_habitation(attrs)
      rec = Habitation.find_or_initialize_by(codigo: attrs[:codigo])
      is_new = rec.new_record?
      rec.assign_attributes(attrs)

      if @strict_mode
        rec.save!
      else
        rec.save(validate: false)
      end

      is_new ? :created : :updated
    end

    def sync_addresses_for_codes(address_by_code)
      return if address_by_code.blank?

      codes = address_by_code.keys
      records = Habitation.where(codigo: codes).includes(:address).index_by(&:codigo)

      address_by_code.each do |codigo, attrs|
        rec = records[codigo]
        next if rec.nil? || attrs.blank?

        upsert_address_for_habitation(rec, attrs)
      end
    end

    def upsert_address_for_habitation(habitation, attrs)
      address = habitation.address || habitation.build_address
      address.assign_attributes(attrs)
      @strict_mode ? address.save! : address.save(validate: false)
    rescue => e
      @stats[:failed] += 1
      say_status :error, "Falha ao salvar address codigo #{habitation.codigo}: #{e.class} - #{e.message}", :red
    end

    def fetch_list(pagina)
      list_payload = {
        'fields' => [],
        'order' => { 'Bairro' => 'asc' },
        'paginacao' => { 'pagina' => pagina, 'quantidade' => 50 }
      }

      fetch_json(
        LISTAR_PATH,
        params: {
          key: VISTA_KEY,
          pesquisa: list_payload.to_json,
          showtotal: 1,
          showSuspended: 1
        }
      )
    end

    def fetch_details(codigo)
      payload = {
        'fields' => [
          # Endereco
          'TipoEndereco', 'Endereco', 'Numero', 'Bairro', 'BairroComercial', 'Cidade',
          'UF', 'Pais', 'CEP', 'Complemento', 'Bloco', 'Lote', 'Imediacoes',
          'Latitude', 'Longitude', 'TituloSite',
          # Comodos/Caracteristicas
          'Dormitorios', 'Suites', 'TotalBanheiros', 'BanheiroSocialQtd', 'Vagas',
          'AreaPrivativa', 'AreaTotal', 'Decorado',
          # Valores & situacao
          'Status', 'Situacao', 'ValorVenda', 'ValorVendaAnterior', 'ValorLocacao',
          'ValorTotalAluguel', 'ValorPromocional', 'ValorCondominio', 'ValorIptu',
          # Empreendimento/Outros
          'Empreendimento', 'CodigoEmpreendimento', 'Lancamento', 'AptosAndar',
          'AptosEdificio', 'Garden', 'QuadraMar', 'SemMobilia',
          # Construtora/Proprietario
          'Construtora', 'CodigoProprietario', 'Proprietario',
          { 'proprietarios' => ['Nome', 'Email', 'Celular', 'FoneComercial', 'FoneResidencial'] },
          # Web/Descricoes
          'InscricaoImobiliaria', 'DescricaoEmpreendimento', 'DescricaoWeb',
          'Caracteristicas', 'InfraEstrutura', 'CaracteristicaUnica', 'Observacoes',
          # Destaques de localizacao
          # Removidos para evitar erro 400 (Campos customizados que podem nao existir)
          
          # Flags site

          'FestivalSalute', 'ExibirNoSite', 'ExibirNoSiteSalute', 'DestaqueWeb',
          # Config
          'Categoria', 'CategoriaGrupo', 'DataCadastro', 'DataAtualizacao', 'DataEntrega', 'TourVirtual',
          { 'Video' => ['Video', 'Tipo'] },
          { 'Foto' => ['Foto', 'FotoPequena', 'Destaque', 'Ordem'] },
          { 'FotoEmpreendimento' => ['Foto', 'FotoPequena', 'Destaque', 'Ordem'] },
          'CodigoCorretor', 'CaptadorAccountId', 'Agenciador',
          'CodigoDWV', 'ImovelDWV', 'TemPlaca'
        ]
      }

      fetch_json(
        DETALHES_PATH,
        method: :get,
        params: {
          key: VISTA_KEY,
          imovel: codigo,
          showSuspended: 1,
          pesquisa: payload.to_json
        }
      )
    end

    def fetch_details_batch(codigos)
      return {} if codigos.blank?

      workers_count = [@concurrency, codigos.size].min
      input_queue = Queue.new
      output_queue = Queue.new

      codigos.each { |codigo| input_queue << codigo }
      workers_count.times { input_queue << nil }

      workers = workers_count.times.map do
        Thread.new do
          while (codigo = input_queue.pop)
            begin
              details = fetch_details(codigo)
              output_queue << [codigo, details]
            rescue => e
              output_queue << [codigo, nil, e]
            end
          end
        end
      end

      results = {}
      codigos.size.times do
        codigo, details, error = output_queue.pop
        if error
          say_status :error, "Erro buscando detalhes codigo #{codigo}: #{error.class} - #{error.message}", :red
          next
        end
        results[codigo] = details
      end

      workers.each(&:join)
      results
    end

    def fetch_json(path, method: :get, params:)
      url = URI.join(VISTA_HOST, path).to_s
      
      # For GET, params go in query string. For POST, payload.
      if method == :get
        qs  = params.map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join('&')
        full_url = "#{url}?#{qs}"
        payload = nil
      else
        full_url = url
        payload = params
      end

      with_retries do
        resp = RestClient::Request.execute(
          method: method,
          url: full_url,
          payload: payload,
          headers: HEADERS,
          timeout: TIMEOUT,
          open_timeout: TIMEOUT
        )
        JSON.parse(resp.body)
      end
    rescue RestClient::ExceptionWithResponse => e
      say_status :error, "HTTP #{e.http_code} em #{path}: #{e.message}", :red
      nil
    rescue JSON::ParserError => e
      say_status :error, "JSON invalido em #{path}: #{e.message}", :red
      nil
    end

    def with_retries
      tries = 0
      begin
        yield
      rescue RestClient::Exceptions::Timeout, RestClient::TooManyRequests, Errno::ECONNRESET => e
        tries += 1
        raise if tries > MAX_RETRIES
        sleep(0.5 * (2 ** (tries - 1)))
        retry
      end
    end

    def safe_int(v)
      v&.to_s&.gsub(/[^\d]/, '').presence&.to_i
    end

    def safe_float(v)
      s = v.to_s.tr(',', '.')
      s =~ /\d/ ? s.to_f : nil
    end

    def safe_bool(v)
      case v
      when true, 'Sim', 'True', 'true', 1, '1' then true
      when false, 'Nao', 'False', 'false', 0, '0', nil, '' then false
      else !!v
      end
    end

    def safe_string(v)
      return nil if v.blank?
      s = v.to_s.strip
      (s == '.' || s.empty?) ? nil : s
    end

    def safe_date(v)
      return nil if v.blank?
      Time.zone.parse(v.to_s) rescue nil
    end

    def parse_money_to_cents(v)
      return nil if v.blank?
      clean = v.to_s.gsub(/[^\d.,]/, '').tr(',', '.')
      (clean.to_f * 100).to_i
    end

    def sanitize_html(text)
      ActionView::Base.full_sanitizer.sanitize(text.to_s)
    end

    def format_photos(photos_data)
      return [] if photos_data.blank?

      photos_array =
        if photos_data.is_a?(Hash)
          photos_data.values
        elsif photos_data.is_a?(Array)
          photos_data.map { |a| a.is_a?(Array) ? a[1] : a }
        else
          []
        end

      photos_array.map.with_index do |photo, index|
        next unless photo.is_a?(Hash)

        url = photo['Foto'] || photo['url'] || photo['Url']
        next if url.blank?

        {
          url: url,
          url_pequena: photo['FotoPequena'],
          descricao: photo['Descricao'],
          principal: (photo['Destaque'] == 'Sim' || photo['Principal'] == true),
          ordem: photo['Ordem']&.to_i || index + 1
        }
      end.compact
    end

    def format_videos(video_data)
      return [] if video_data.blank?

      Array(video_data).map do |item|
        entry = item.is_a?(Array) ? item[1] : item
        next unless entry.is_a?(Hash)

        {
          url: entry['Video'],
          tipo: entry['Tipo']
        }
      end.compact
    end

    def normalize_characteristic_name(name)
      name.to_s
          .downcase
          .unicode_normalize(:nfkd)
          .encode('ASCII', replace: '')
          .gsub(/\s+/, '_')
          .gsub(/[^a-z0-9_]/, '')
    end

    def extract_characteristics(data)
      return {} unless data['Caracteristicas'].is_a?(Hash)

      chars = {}
      data['Caracteristicas'].each do |key, value|
        next unless value.to_s.downcase == 'sim'

        normalized = normalize_characteristic_name(key)
        chars[normalized] = normalized
      end

      chars
    end

    def extract_infrastructure(data)
      return [] unless data['InfraEstrutura'].is_a?(Hash)

      data['InfraEstrutura'].each_with_object([]) do |(key, value), acc|
        acc << key if value.to_s.downcase == 'sim'
      end
    end

    def characteristic_true?(data, *keys)
      return false unless data['Caracteristicas'].is_a?(Hash)

      keys.any? { |key| data['Caracteristicas'][key].to_s.downcase == 'sim' }
    end

    def build_params(list_item, hb)
      photos = format_photos(hb['Foto'])
      photos_emp = format_photos(hb['FotoEmpreendimento'])
      videos = format_videos(hb['Video'])

      valor_venda_cents = parse_money_to_cents(hb['ValorVenda'])
      area_total = safe_float(hb['AreaTotal'])
      valor_por_m2 = (valor_venda_cents && area_total && area_total > 0) ? (valor_venda_cents / area_total).round : nil

      owner_data = extract_owner_data(hb['proprietarios'])

      categoria = safe_string(hb['Categoria'])
      tipo = categoria == 'Empreendimento' ? 'Empreendimento' : 'Unitário'
      address_attrs = extract_address_attributes(hb)

      {
        slug: build_slug(hb),
        codigo: hb['Codigo'].to_s,
        categoria: categoria,
        tipo: tipo,
        status: safe_string(hb['Status']),
        situacao: safe_string(hb['Situacao']),
        codigo_empreendimento: hb['CodigoEmpreendimento'],
        nome_empreendimento: safe_string(hb['Empreendimento']),

        tipo_endereco: hb['TipoEndereco'],
        endereco: address_attrs[:logradouro],
        numero: address_attrs[:numero],
        complemento: address_attrs[:complemento],
        bairro: address_attrs[:bairro],
        bairro_comercial: address_attrs[:bairro_comercial],
        bloco: hb['Bloco'],
        lote: hb['Lote'],
        imediacoes: address_attrs[:imediacoes].join(', '),
        cidade: address_attrs[:cidade],
        uf: address_attrs[:uf],
        cep: address_attrs[:cep],
        pais: address_attrs[:pais],
        latitude: address_attrs[:latitude],
        longitude: address_attrs[:longitude],

        dormitorios_qtd: safe_int(hb['Dormitorios']),
        suites_qtd: safe_int(hb['Suites']),
        banheiros_qtd: safe_int(hb['TotalBanheiros']),
        banheiro_social_qtd: safe_int(hb['BanheiroSocialQtd']),
        vagas_qtd: safe_int(hb['Vagas']),
        area_privativa_m2: safe_float(hb['AreaPrivativa']),
        area_total_m2: area_total,

        aptos_andar: safe_int(hb['AptosAndar']),
        aptos_edificio: safe_int(hb['AptosEdificio']),

        valor_venda_cents: valor_venda_cents,
        valor_venda_anterior_cents: parse_money_to_cents(hb['ValorVendaAnterior']),
        valor_locacao_cents: parse_money_to_cents(hb['ValorLocacao']),
        valor_total_aluguel_cents: parse_money_to_cents(hb['ValorTotalAluguel']),
        valor_promocional_cents: parse_money_to_cents(hb['ValorPromocional']),
        valor_condominio_cents: parse_money_to_cents(hb['ValorCondominio']),
        valor_iptu_cents: parse_money_to_cents(hb['ValorIptu']),
        valor_por_m2_cents: valor_por_m2,

        constructor_id: resolve_constructor(hb['Construtora']),
        construtora: hb['Construtora'],
        proprietario: hb['Proprietario'],
        proprietario_codigo: hb['CodigoProprietario'],
        proprietario_celular: owner_data['Celular'],
        proprietario_telefone_comercial: owner_data['FoneComercial'],
        proprietario_telefone_residencial: owner_data['FoneResidencial'],
        proprietario_email: owner_data['Email'],
        inscricao_imobiliaria: hb['InscricaoImobiliaria'],

        descricao_empreendimento: sanitize_html(hb['DescricaoEmpreendimento']),
        descricao_web: sanitize_html(hb['DescricaoWeb']),
        descricao_interna: nil,
        titulo_anuncio: hb['TituloSite'],
        observacoes: sanitize_html(hb['Observacoes']),

        caracteristicas: extract_characteristics(hb),
        infra_estrutura: extract_infrastructure(hb),
        caracteristica_unica: safe_string(hb['CaracteristicaUnica']),

        destaque_localizacao: {
          "3_avenida": hb['3Avenida'],
          "arriba": hb['Arriba'],
          "avenida_brasil": hb['AvenidaBrasil'],
          "bairro_fazenda_itajai": hb['BairroFazendaItajai'],
          "balneario_picarras": hb['BalnearioPicarras'],
          "barra": hb['Barra'],
          "barra_norte": hb['BarraNorte'],
          "barra_sul": hb['BarraSul'],
          "cabecudas": hb['Cabecudas'],
          "camboriu": hb['Camboriu'],
          "centro": hb['Centro'],
          "estaleirinho": hb['Estaleirinho'],
          "frente_mar_avenida_atlantica": hb['FrenteMarAvenidaAtlantica'],
          "itajai": hb['Itajai'],
          "itapema": hb['Itapema'],
          "nacoes": hb['Nacoes'],
          "pioneiros": hb['Pioneiros'],
          "praia_brava": hb['PraiaBrava'],
          "praia_dos_amores": hb['PraiaDosAmores'],
          "quadra_mar": hb['QuadraMar'],
          "vista_frente_mar": hb['VistaFrenteMar']
        },

        pictures: photos,
        fotos_empreendimento: photos_emp,
        videos: videos,

        exibir_no_site_flag: safe_bool(hb['ExibirNoSite']),
        exibir_no_site_salute_flag: safe_bool(hb['ExibirNoSiteSalute']),
        destaque_web_flag: safe_bool(hb['DestaqueWeb']),
        lancamento_flag: safe_bool(hb['Lancamento']),
        aceita_permuta_flag: characteristic_true?(hb, 'AceitaPermuta', 'Aceita Permuta'),
        aceita_financiamento_flag: characteristic_true?(hb, 'AceitaFinanciamento', 'Aceita Financiamento'),
        mobiliado_flag: characteristic_true?(hb, 'Mobiliado'),
        decorado_flag: safe_bool(hb['Decorado']),
        garden_flag: safe_bool(hb['Garden']),
        quadra_mar_flag: safe_bool(hb['QuadraMar']),
        sem_mobilia_flag: safe_bool(hb['SemMobilia']) || safe_bool(list_item['SemMobilia']),
        festival_salute_flag: safe_bool(hb['FestivalSalute']),
        tem_placa_flag: safe_bool(hb['TemPlaca']),
        piscina_flag: characteristic_true?(hb, 'Piscina'),
        lavabo_flag: characteristic_true?(hb, 'Lavabo'),
        varanda_gourmet_flag: characteristic_true?(hb, 'Varanda Gourmet', 'VarandaGourmet'),

        terceira_avenida_flag: safe_bool(hb['3Avenida']),
        arriba_flag: safe_bool(hb['Arriba']),
        avenida_brasil_flag: safe_bool(hb['AvenidaBrasil']),
        bairro_fazenda_itajai_flag: safe_bool(hb['BairroFazendaItajai']),
        balneario_picarras_flag: safe_bool(hb['BalnearioPicarras']),
        barra_flag: safe_bool(hb['Barra']),
        barra_norte_flag: safe_bool(hb['BarraNorte']),
        barra_sul_flag: safe_bool(hb['BarraSul']),
        cabecudas_flag: safe_bool(hb['Cabecudas']),
        camboriu_flag: safe_bool(hb['Camboriu']),
        centro_flag: safe_bool(hb['Centro']),
        estaleirinho_flag: safe_bool(hb['Estaleirinho']),
        frente_mar_avenida_atlantica_flag: safe_bool(hb['FrenteMarAvenidaAtlantica']),
        itajai_flag: safe_bool(hb['Itajai']),
        itapema_flag: safe_bool(hb['Itapema']),
        nacoes_flag: safe_bool(hb['Nacoes']),
        pioneiros_flag: safe_bool(hb['Pioneiros']),
        praia_brava_flag: safe_bool(hb['PraiaBrava']),
        praia_dos_amores_flag: safe_bool(hb['PraiaDosAmores']),
        vista_frente_mar_flag: safe_bool(hb['VistaFrenteMar']),

        categoria_grupo: hb['CategoriaGrupo'],
        data_entrega: safe_date(hb['DataEntrega']),
        tour_virtual: hb['TourVirtual'],

        data_atualizacao_crm: safe_date(hb['DataAtualizacao']) || Time.current,
        data_cadastro_crm: safe_date(hb['DataCadastro']),

        codigo_corretor: hb['CodigoCorretor'],
        admin_user_id: @admin_user_id_by_vista_id[hb['CodigoCorretor'].to_s],
        captador_account_id: hb['CaptadorAccountId'],
        agenciador: hb['Agenciador'],

        codigo_dwv: hb['CodigoDWV'],
        imovel_dwv: hb['ImovelDWV'],
        status_vista: hb['Status'],
        _address_attrs: address_attrs
      }
    end

    def extract_address_attributes(hb)
      {
        tipo_endereco: safe_string(hb['TipoEndereco']),
        logradouro: safe_string(hb['Endereco']),
        numero: safe_string(hb['Numero']),
        complemento: safe_string(hb['Complemento']),
        bairro: safe_string(hb['Bairro']),
        bairro_comercial: safe_string(hb['BairroComercial']),
        cidade: safe_string(hb['Cidade']),
        uf: safe_string(hb['UF']),
        cep: normalize_cep(hb['CEP']),
        pais: hb['Pais'].presence || 'Brasil',
        latitude: hb['Latitude'],
        longitude: hb['Longitude'],
        imediacoes: normalize_imediacoes(hb['Imediacoes'])
      }
    end

    def extract_owner_data(raw_owner_data)
      case raw_owner_data
      when Hash
        first_value = raw_owner_data.values.first
        first_value.is_a?(Hash) ? first_value : {}
      when Array
        first_hash = raw_owner_data.find { |item| item.is_a?(Hash) }
        first_hash || {}
      else
        {}
      end
    end

    def normalize_imediacoes(raw_value)
      case raw_value
      when Array
        raw_value
      when String
        raw_value.split(/[,\n;]+/)
      else
        Array(raw_value)
      end.map { |item| item.to_s.strip }.reject(&:blank?).uniq
    end

    def build_slug(hb)
      parts = [hb['Categoria'], hb['Cidade'], hb['Bairro'], hb['Codigo']].compact
      parts.join('-').parameterize
    end

    def start_progress!
      say_status :info, "Progress ID: #{@progress_id}", :yellow
      say_status :info, "Acompanhar: bundle exec rake 'vista:progress[#{@progress_id}]'", :yellow
      @progress_started_mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @progress_state = {
        progress_id: @progress_id,
        status: 'running',
        started_at: Time.current,
        total_pages: 0,
        total_records: 0,
        current_page: 0,
        processed: 0,
        created: 0,
        updated: 0,
        failed: 0
      }
      write_progress(@progress_state)
    end

    def finish_progress!(total_importados)
      update_progress(
        status: 'done',
        finished_at: Time.current,
        processed: total_importados,
        created: @stats[:created],
        updated: @stats[:updated],
        failed: @stats[:failed]
      )
      emit_progress_line(force: true)
      puts
    end

    def update_progress(payload)
      @progress_state = @progress_state.merge(payload).merge(updated_at: Time.current)
      write_progress(@progress_state)
    end

    def emit_progress_line(force: false)
      return unless @progress_started_mono

      now_mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # Evita overhead alto no terminal mantendo atualização fluida
      return if !force && defined?(@last_progress_render_mono) && (now_mono - @last_progress_render_mono) < 0.1

      total = @progress_state[:total_records].to_i
      processed = @progress_state[:processed].to_i
      percent = total.positive? ? (processed.to_f / total) : 0.0

      elapsed = now_mono - @progress_started_mono
      rate = elapsed.positive? ? (processed / elapsed) : 0.0
      remaining = [total - processed, 0].max
      eta = rate.positive? && total.positive? ? (remaining / rate) : 0.0

      bar_width = progress_bar_width
      filled = [(percent * bar_width).round, bar_width].min
      bar = ("#" * filled).ljust(bar_width, "-")

      print format(
        "\r[%<bar>s] [%<processed>d/%<total>d] [%<percent>.2f%%] [%<elapsed>s] [%<eta>s] [%<rate>6.2f/s]",
        bar: bar,
        processed: processed,
        total: total,
        percent: (percent * 100),
        elapsed: format_duration(elapsed),
        eta: format_duration(eta),
        rate: rate
      )
      $stdout.flush
      @last_progress_render_mono = now_mono
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

    def progress_key
      "vista:import:#{@progress_id}"
    end

    def write_progress(payload)
      Rails.cache.write(progress_key, payload, expires_in: PROGRESS_TTL)
    end

    def read_progress
      Rails.cache.read(progress_key)
    end
  end
end

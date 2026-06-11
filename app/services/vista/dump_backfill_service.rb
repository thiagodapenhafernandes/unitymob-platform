require "csv"
require "set"

module Vista
  class DumpBackfillService
    DEFAULT_DUMP_DIR = DumpImportService::DEFAULT_DUMP_DIR

    CADIMO_FIELD_GROUPS = {
      base: %w[
        CODIGO CODIGO_C CODIGO_M CORRETORES_DO_IMOVEL STATUS SITUACAO
        ENDERECO_TIPO ENDERECO NUM_ENDERECO COMP_ENDERECO BAIRRO BAIRRO_COMERCIAL
        CIDADE UF CEP PAIS GMAPS_LAT GMAPS_LNG IMEDIACOES BLOCO LOTE
        CARACTERISTICA_UNICA TOURVIRTUAL LINK_VIDEO ID_VIDEOW
        TIPO_PUBLICACAO_VIVA_REAL DIVULGAR_ENDERECO_VIVA_REAL
        MODELO_IMOVELWEB TIPO_PUBLICACAO_IMOVELWEB MOSTRAR_MAPA
        TIPO_OFERTA_ZAP DESTAQUE_CHAVES_NA_MAO CHAVES_NA_MAO_PERIODO_LOCACAO
        MODELO_CASA_MINEIRA TIPO_PUBLICACAO_LOFT DIVULGAR_ENDERECO_LOFT
        AC_PERMUTA_TIPO_IMO AC_PERMUTA_LOCALIZACAO AC_PERMUTA_VALOR
        AC_PERMUTA_QNT_DORMITORIOS AC_PERMUTA_QNT_SUITES AC_PERMUTA_QNT_GARAGENS
        ACEITA_PERMUTA_AUTO ACEITA_PERMUTA_OUTROS AC_PERMUTA_TIPO_AUT
        ACEITA_DACAO ANO_MIN_VEICULO_PERMUTA
        COMISSAO_CAPTADOR COMISSAO_CORRETOR PERCENTUAL_COMISSAO
        VLR_COMISSAO VLR_LIVRE_PROPRIETARIO COM_ADMINISTRACAO SEM_ADMINISTRACAO
        OBS_VENDA OBS_LOCACAO OBSERVACOES
      ],
      characteristics: %w[
        ADEGA AGUA_QUENTE ALARME AQUECIMENTO_CENTRAL AQUECIMENTO_ELETRICO
        AR_CENTRAL AR_CONDICIONADO AREA_SERVICO ARMARIOS_EMBUTIDOS BANHO_AUXILIAR
        BANHO_SOCIAL BANHEIRO_SOCIAL CHURRASQUEIRA_A_CARVAO CHURRASQUEIRA_A_GAS
        CLOSET COPA COPA_COZINHA COZINHA COZINHA_AMERICANA COZINHA_PLANEJADA
        DEPENDENCIA DEPOSITO DESPENSA DORMITORIO_ARMARIO ENTRADA_SERVICO
        GABINETE HIDRO HIDRO_SUITE HOME_THEATER LIVING_LAREIRA LIVING_LAVABO
        SACADA_ABERTA SACADA_FECHADA SACADA_INTEGRADA SALA_JANTAR SALA_TV
        SPLIT VARANDA VARANDAS WC_EMPREGADA MOBILIADO DECORADO GARDEN
        QUADRA_MAR SEM_MOBILIA VISTA_MAR VISTA_FRENTE_MAR
      ],
      infrastructure: %w[
        BICICLETARIO CIRCUITO_INTERNO_TV ELEVADOR_COM ELEVADOR_SERVICO
        ESPACO_GOURMET ESTACIONAMENTO GAS_CENTRAL GERADOR_ENERGIA INTERFONE
        JARDIM PISCINA_AQUECIDA PISCINA_COLETIVA PISCINA_INFANTIL PLAYGROUD
        POCO_ARTESIANO PORTARIA PORTARIA_24HS PORTARIA_ED QUADRA_ESPORTES
        QUADRA_POLIESPORTIVA QUADRA_TENIS QUIOSQUE SALA_GINASTICA SALA_JOGOS
        SALAO_FESTAS SALAO_BRINQUEDOS SAUNA SAUNA_COL SEGURANCA TERRACO_COL
        VIGILANCIA_24H
      ],
      location_highlights: %w[
        3_AVENIDA ARRIBA AVENIDA_BRASIL BAIRRO_FAZENDA_ITAJAI
        BALNEARIO_PICARRAS BARRA BARRA_NORTE BARRA_SUL CABECUDAS CAMBORIU
        CENTRO ESTALEIRINHO FRENTE_MAR_AVENIDA_ATLANTICA ITAJAI ITAPEMA
        NACOES PIONEIROS PRAIA_BRAVA PRAIA_DOS_AMORES VISTA_FRENTE_MAR
      ]
    }.freeze

    CADIMO_FIELDS = CADIMO_FIELD_GROUPS.values.flatten.uniq.freeze

    CADCLI_FIELDS = %w[
      CODIGO_C NOME CELULAR FONE_R FONE_C FONE_PRINCIPAL EMAIL_R EMAIL_C
    ].freeze

    LOCATION_FLAG_COLUMNS = {
      "3_AVENIDA" => :terceira_avenida_flag,
      "ARRIBA" => :arriba_flag,
      "AVENIDA_BRASIL" => :avenida_brasil_flag,
      "BAIRRO_FAZENDA_ITAJAI" => :bairro_fazenda_itajai_flag,
      "BALNEARIO_PICARRAS" => :balneario_picarras_flag,
      "BARRA" => :barra_flag,
      "BARRA_NORTE" => :barra_norte_flag,
      "BARRA_SUL" => :barra_sul_flag,
      "CABECUDAS" => :cabecudas_flag,
      "CAMBORIU" => :camboriu_flag,
      "CENTRO" => :centro_flag,
      "ESTALEIRINHO" => :estaleirinho_flag,
      "FRENTE_MAR_AVENIDA_ATLANTICA" => :frente_mar_avenida_atlantica_flag,
      "ITAJAI" => :itajai_flag,
      "ITAPEMA" => :itapema_flag,
      "NACOES" => :nacoes_flag,
      "PIONEIROS" => :pioneiros_flag,
      "PRAIA_BRAVA" => :praia_brava_flag,
      "PRAIA_DOS_AMORES" => :praia_dos_amores_flag,
      "VISTA_FRENTE_MAR" => :vista_frente_mar_flag
    }.freeze

    Result = Struct.new(
      :dry_run,
      :scanned,
      :eligible,
      :updated,
      :failed,
      :addresses_upserted,
      :characteristics_filled,
      :infrastructure_filled,
      :portal_flags_filled,
      :owner_contacts_filled,
      :broker_fields_filled,
      :errors,
      keyword_init: true
    )

    def initialize(dump_dir: DEFAULT_DUMP_DIR, dry_run: true, only_imported: true, limit: nil)
      dump_path = Pathname.new(dump_dir.to_s)
      @dump_dir = dump_path.absolute? ? dump_path : Rails.root.join(dump_path)
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @only_imported = ActiveModel::Type::Boolean.new.cast(only_imported)
      @limit = limit.to_i.positive? ? limit.to_i : nil
      @clients = {}
      @admin_user_id_by_vista_id = {}
    end

    def call
      validate_dump!
      load_reference_data

      result = Result.new(
        dry_run: @dry_run,
        scanned: 0,
        eligible: 0,
        updated: 0,
        failed: 0,
        addresses_upserted: 0,
        characteristics_filled: 0,
        infrastructure_filled: 0,
        portal_flags_filled: 0,
        owner_contacts_filled: 0,
        broker_fields_filled: 0,
        errors: []
      )

      each_row(cadimo_path, "CADIMO", CADIMO_FIELDS) do |row|
        result.scanned += 1
        code = normalize_code(row["CODIGO"])
        next if code.blank?

        habitation = target_scope.find_by(codigo: code)
        next unless habitation

        result.eligible += 1
        break if @limit && result.updated >= @limit

        backfill_habitation(habitation, row, result)
      end

      result
    end

    private

    def validate_dump!
      [cadimo_path, cadcli_path].each do |path|
        raise ArgumentError, "Arquivo nao encontrado: #{path}" unless File.exist?(path)
      end
    end

    def load_reference_data
      each_row(cadcli_path, "CADCLI", CADCLI_FIELDS) do |row|
        code = normalize_code(row["CODIGO_C"])
        @clients[code] = row if code.present?
      end

      @admin_user_id_by_vista_id = AdminUser.where.not(vista_id: [nil, ""]).pluck(:vista_id, :id).to_h
    end

    def target_scope
      scope = Habitation.all
      return scope unless @only_imported

      scope.where("last_sync_message LIKE ?", "%Importado do dump Vista%")
    end

    def backfill_habitation(habitation, row, result)
      attrs = habitation_attributes(row)
      address_attrs = address_attributes(row)
      owner_attrs = owner_contact_attributes(row)
      broker_attrs = broker_attributes(row)

      if @dry_run
        increment_stats(result, habitation, attrs, address_attrs, owner_attrs, broker_attrs)
        result.updated += 1
        return
      end

      Habitation.transaction do
        habitation.skip_auto_audit = true
        habitation.assign_attributes(attrs.merge(owner_attrs).merge(broker_attrs))
        habitation.save!

        if valid_address_attrs?(address_attrs)
          address = habitation.address || habitation.build_address
          address.assign_attributes(address_attrs)
          address.save!
        end

        update_proprietor_contact(habitation.proprietor, owner_attrs)
      end

      increment_stats(result, habitation, attrs, address_attrs, owner_attrs, broker_attrs)
      result.updated += 1
    rescue StandardError => e
      result.failed += 1
      result.errors << { codigo: habitation.codigo, erro: e.message }
    end

    def increment_stats(result, habitation, attrs, address_attrs, owner_attrs, broker_attrs)
      result.addresses_upserted += 1 if valid_address_attrs?(address_attrs)
      result.characteristics_filled += 1 if empty_jsonish?(habitation[:caracteristicas]) && attrs[:caracteristicas].present?
      result.infrastructure_filled += 1 if empty_jsonish?(habitation[:infra_estrutura]) && attrs[:infra_estrutura].present?
      result.portal_flags_filled += 1 if attrs.slice(*portal_boolean_fields).values.any?
      result.owner_contacts_filled += 1 if owner_attrs.values.any?(&:present?)
      result.broker_fields_filled += 1 if broker_attrs.values.any?(&:present?)
    end

    def habitation_attributes(row)
      characteristics = selected_labels(row, CADIMO_FIELD_GROUPS[:characteristics], category: "feature")
      infrastructure = selected_labels(row, CADIMO_FIELD_GROUPS[:infrastructure], category: "infrastructure")
      location_highlights = selected_labels(row, CADIMO_FIELD_GROUPS[:location_highlights], category: "feature")

      {
        caracteristicas: characteristics.index_by(&:itself),
        infra_estrutura: infrastructure,
        caracteristica_unica: split_list(row["CARACTERISTICA_UNICA"]),
        destaque_localizacao: location_highlights.index_by(&:itself),
        tour_virtual: present_value(row["TOURVIRTUAL"]) || present_value(row["LINK_VIDEO"]) || present_value(row["ID_VIDEOW"]),
        valor_aceito_permuta_cents: money_cents(row["AC_PERMUTA_VALOR"]),
        permuta_valor_cents: money_cents(row["AC_PERMUTA_VALOR"]),
        permuta_localizacao: present_value(row["AC_PERMUTA_LOCALIZACAO"]),
        permuta_dormitorios_qtd: integer_value(row["AC_PERMUTA_QNT_DORMITORIOS"]),
        permuta_suites_qtd: integer_value(row["AC_PERMUTA_QNT_SUITES"]),
        permuta_garagens_qtd: integer_value(row["AC_PERMUTA_QNT_GARAGENS"]),
        aceita_permuta_imovel_flag: yes?(row["AC_PERMUTA_TIPO_IMO"]) || active_value(row["AC_PERMUTA_TIPO_IMO"]).present?,
        aceita_permuta_veiculo_flag: yes?(row["ACEITA_PERMUTA_AUTO"]),
        aceita_permuta_outros_flag: yes?(row["ACEITA_PERMUTA_OUTROS"]),
        tipo_veiculo_aceito_permuta: present_value(row["AC_PERMUTA_TIPO_AUT"]),
        ano_minimo_veiculo_aceito_permuta: integer_value(row["ANO_MIN_VEICULO_PERMUTA"]),
        aceita_doacao_flag: yes?(row["ACEITA_DACAO"]),
        captador_commission_percentage: commission_percentage(row["COMISSAO_CAPTADOR"], row["PERCENTUAL_COMISSAO"]),
        broker_commission_percentage: decimal_value(row["COMISSAO_CORRETOR"]),
        valor_comissao_cents: commission_amount_cents(row),
        valor_livre_proprietario_cents: money_cents(row["VLR_LIVRE_PROPRIETARIO"]),
        salute_rental_management_flag: rental_management_flag(row),
        publicar_zapimoveis: active_value(row["TIPO_OFERTA_ZAP"]).present?,
        publicar_viva_real_vrsync: active_value(row["TIPO_PUBLICACAO_VIVA_REAL"]).present? || active_value(row["DIVULGAR_ENDERECO_VIVA_REAL"]).present?,
        publicar_imovelweb: active_value(row["TIPO_PUBLICACAO_IMOVELWEB"]).present? || active_value(row["MODELO_IMOVELWEB"]).present? || active_value(row["MOSTRAR_MAPA"]).present?,
        publicar_chaves_na_mao: active_value(row["DESTAQUE_CHAVES_NA_MAO"]).present? || active_value(row["CHAVES_NA_MAO_PERIODO_LOCACAO"]).present?,
        publicar_casa_mineira: active_value(row["MODELO_CASA_MINEIRA"]).present?,
        publicar_loft: active_value(row["TIPO_PUBLICACAO_LOFT"]).present? || active_value(row["DIVULGAR_ENDERECO_LOFT"]).present?,
        destaque_chaves_na_mao: yes_no_option(row["DESTAQUE_CHAVES_NA_MAO"]),
        periodo_locacao_chaves_na_mao: active_value(row["CHAVES_NA_MAO_PERIODO_LOCACAO"]),
        modelo_casa_mineira: active_value(row["MODELO_CASA_MINEIRA"]),
        tipo_publicacao_viva_real: active_value(row["TIPO_PUBLICACAO_VIVA_REAL"]),
        divulgar_endereco_viva_real: active_value(row["DIVULGAR_ENDERECO_VIVA_REAL"]),
        tipo_publicacao_imovelweb: active_value(row["TIPO_PUBLICACAO_IMOVELWEB"]) || active_value(row["MODELO_IMOVELWEB"]),
        mostrar_mapa_imovelweb: active_value(row["MOSTRAR_MAPA"])
      }.merge(location_flag_attributes(row)).compact
    end

    def address_attributes(row)
      {
        tipo_endereco: present_value(row["ENDERECO_TIPO"]),
        logradouro: present_value(row["ENDERECO"]),
        numero: present_value(row["NUM_ENDERECO"]),
        complemento: present_value(row["COMP_ENDERECO"]),
        bairro: present_value(row["BAIRRO"]),
        bairro_comercial: present_value(row["BAIRRO_COMERCIAL"]),
        cidade: present_value(row["CIDADE"]),
        uf: present_value(row["UF"]).to_s.first(2).presence,
        cep: present_value(row["CEP"]),
        pais: present_value(row["PAIS"]) || "Brasil",
        latitude: decimal_value(row["GMAPS_LAT"]),
        longitude: decimal_value(row["GMAPS_LNG"]),
        imediacoes: split_list(row["IMEDIACOES"])
      }.compact
    end

    def owner_contact_attributes(row)
      client = @clients[normalize_code(row["CODIGO_C"])] || {}

      {
        proprietario_celular: present_value(client["CELULAR"]) || present_value(client["FONE_PRINCIPAL"]),
        proprietario_telefone_comercial: present_value(client["FONE_C"]),
        proprietario_telefone_residencial: present_value(client["FONE_R"]),
        proprietario_email: present_value(client["EMAIL_R"]) || present_value(client["EMAIL_C"])
      }.compact
    end

    def broker_attributes(row)
      code = normalize_code(row["CODIGO_M"])
      {
        codigo_corretor: code,
        admin_user_id: @admin_user_id_by_vista_id[code],
        corretor_nome: present_value(row["CORRETORES_DO_IMOVEL"])
      }.compact
    end

    def location_flag_attributes(row)
      LOCATION_FLAG_COLUMNS.each_with_object({}) do |(column, attr), attrs|
        attrs[attr] = true if yes?(row[column])
      end
    end

    def update_proprietor_contact(proprietor, owner_attrs)
      return unless proprietor

      proprietor.mobile_phone ||= owner_attrs[:proprietario_celular]
      proprietor.business_phone ||= owner_attrs[:proprietario_telefone_comercial]
      proprietor.residential_phone ||= owner_attrs[:proprietario_telefone_residencial]
      proprietor.email ||= owner_attrs[:proprietario_email]
      proprietor.save! if proprietor.changed?
    end

    def valid_address_attrs?(attrs)
      attrs[:logradouro].present? && attrs[:bairro].present? && attrs[:cidade].present? && attrs[:uf].to_s.length == 2
    end

    def selected_labels(row, columns, category:)
      columns.filter_map do |column|
        next unless yes?(row[column])

        label_for(column, category: category)
      end.uniq
    end

    def label_for(column, category:)
      raw = column.to_s == "PLAYGROUD" ? "PLAYGROUND" : column.to_s

      AttributeOptions::HabitationFeatureNormalizer.label(raw, category: category)
    end

    def portal_boolean_fields
      %i[
        publicar_zapimoveis publicar_viva_real_vrsync publicar_imovelweb
        publicar_chaves_na_mao publicar_casa_mineira publicar_loft
      ]
    end

    def split_list(value)
      present_value(value).to_s.split(/[,\n;]+/).map(&:strip).reject(&:blank?).uniq
    end

    def yes_no_option(value)
      return "sim" if yes?(value)
      return "nao" if no?(value)

      nil
    end

    def commission_percentage(primary_raw, fallback_raw = nil)
      primary = decimal_value(primary_raw)
      fallback = decimal_value(fallback_raw)
      return primary if primary&.positive?
      return fallback if fallback&.positive?

      primary || fallback
    end

    def commission_amount_cents(row)
      structured_amount = money_cents(row["VLR_COMISSAO"])
      return structured_amount if structured_amount.to_i.positive?

      amount_from_notes(row, /valor\s+da\s+comiss[aã]o\??\s*:?\s*([\d.,]+)/i)
    end

    def rental_management_flag(row)
      return true if yes?(row["COM_ADMINISTRACAO"])
      return false if yes?(row["SEM_ADMINISTRACAO"])

      boolean_from_notes(row, /tem\s+administra[cç][aã]o\??\s*:?\s*(sim|s|nao|não|n)/i)
    end

    def amount_from_notes(row, pattern)
      note_texts(row).each do |text|
        match = text.match(pattern)
        next unless match

        cents = money_cents(match[1])
        return cents if cents.to_i.positive?
      end

      nil
    end

    def boolean_from_notes(row, pattern)
      note_texts(row).each do |text|
        normalized = I18n.transliterate(text)
        match = normalized.match(pattern)
        next unless match

        return %w[sim s].include?(match[1].to_s.downcase)
      end

      nil
    end

    def note_texts(row)
      %w[OBS_VENDA OBS_LOCACAO OBSERVACOES].filter_map { |field| present_value(row[field]) }
    end

    def empty_jsonish?(value)
      value.blank? || value == {} || value == []
    end

    def each_row(path, table, wanted_fields)
      buffer = +""
      in_insert = false
      indexes = nil

      File.open(path, "rb") do |file|
        file.each_line do |raw_line|
          line = raw_line.force_encoding(Encoding::Windows_1252).encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

          if !in_insert
            next unless line.start_with?("INSERT INTO `#{table}`")

            columns = line[/INSERT INTO `#{Regexp.escape(table)}` \((.*?)\) VALUES/m, 1].scan(/`([^`]+)`/).flatten
            indexes = wanted_fields.each_with_object({}) do |field, memo|
              index = columns.index(field)
              memo[field] = index if index
            end
            buffer << line.split(" VALUES ", 2).last.to_s
            in_insert = true
          else
            buffer << line
          end

          next unless in_insert && line.rstrip.end_with?(";")

          each_tuple(buffer) do |tuple|
            fields = CSV.parse_line(tuple, col_sep: ",", quote_char: '"', liberal_parsing: true)
            yield indexes.transform_values { |index| clean(fields[index]) }
          end

          buffer.clear
          in_insert = false
        end
      end
    end

    def each_tuple(values_sql)
      sql = values_sql.strip.sub(/;\s*\z/, "")
      depth = 0
      quoted = false
      escaped = false
      start_index = nil

      sql.each_char.with_index do |char, index|
        if quoted
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == '"'
            quoted = false
          end
        else
          case char
          when '"'
            quoted = true
          when "("
            start_index = index + 1 if depth.zero?
            depth += 1
          when ")"
            depth -= 1
            if depth.zero? && start_index
              yield sql[start_index...index]
              start_index = nil
            end
          end
        end
      end
    end

    def clean(value)
      return nil if value.nil?

      string = value.to_s
      return nil if string == "NULL"

      string
        .gsub("\\r", "\r")
        .gsub("\\n", "\n")
        .gsub('\\"', '"')
        .gsub("\\'", "'")
        .gsub("\\\\", "\\")
        .strip
    end

    def present_value(value)
      clean(value).presence
    end

    def active_value(value)
      value = present_value(value)
      return nil if value.blank? || value == "0" || no?(value)

      value
    end

    def normalize_code(value)
      code = present_value(value)
      code.present? && code != "0" ? code : nil
    end

    def yes?(value)
      present_value(value).to_s.casecmp("sim").zero?
    end

    def no?(value)
      present_value(value).to_s.casecmp("nao").zero? || present_value(value).to_s.casecmp("não").zero?
    end

    def integer_value(value)
      number = present_value(value).to_s.gsub(/[^\d-]/, "")
      number.present? ? number.to_i : nil
    end

    def decimal_value(value)
      number = present_value(value).to_s.tr(",", ".").gsub(/[^\d.-]/, "")
      number.present? ? BigDecimal(number) : nil
    rescue ArgumentError
      nil
    end

    def money_cents(value)
      decimal = decimal_value(value)
      return nil unless decimal&.positive?

      (decimal * 100).round.to_i
    end

    def cadimo_path = @dump_dir.join("CADIMO.sql")
    def cadcli_path = @dump_dir.join("CADCLI.sql")
  end
end

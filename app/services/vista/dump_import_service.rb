require "csv"
require "set"

module Vista
  class DumpImportService
    DEFAULT_DUMP_DIR = "crm-saluteim20174-20174-2026-05-27-09-53-30".freeze
    PHOTO_BASE_URL = "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/".freeze

    CADIMO_FIELDS = %w[
      CODIGO CODIGO_C CODIGO_CT CODIGO_EMP CODIGO_M STATUS SITUACAO TIPO
      CATEGORIA ENDERECO_TIPO ENDERECO NUM_ENDERECO COMP_ENDERECO BAIRRO
      BAIRRO_COMERCIAL CIDADE UF CEP PAIS GMAPS_LAT GMAPS_LNG DORMITORIO
      SUITE BANHEIRO_SOCIAL BANHO_SOCIAL VAGAS ELEVADORES AREA_PRIVATIVA
      AREA_TOTAL AREA_TERRENO AREA_CONSTRUIDA VLR_VENDA VLR_ALUGUEL
      VALOR_ALUGUEL VLR_CONDOMINIO VLR_IPTU VLR_TOTAL_ALUGUEL TITULO_SITE
      TITULO_WEB DESCRICAO_PARA_WEB TEXTO_ANUNCIO OBS OBS_VENDA OBS_LOCACAO
      EMPREENDIMENTO DESCRICAO_EMP CONSTRUTORA E_EMPREENDIMENTO DA_WEB
      EXIBIR_NO_SITE_SALUTE EXIBIR_NO_SIT_SALUTE DESTAQUE_WEB LANCAMENTO
      MOBILIADO ACEITA_FINANCIAMENTO ACEITA_PERMUTA TEM_PLACA EXCLUSIVO
      DATA DATA_ATUALIZACAO DH_ATUALIZACAO DATA_ENTREGA CODIGO_DWV IMOVEL_DWV
      CAPTADOR_ACCOUNT_ID CAPTADOR_ACCOUNT_NOME PROFISSIONAIS BOAS
      ACEITAVEIS NAO_TEM_FOTOS
    ].freeze

    CADCLI_FIELDS = %w[
      CODIGO_C NOME DATA RG CPF CELULAR FONE_R FONE_C FONE_PRINCIPAL
      EMAIL_R EMAIL_C CLIENTE PROPRIETARIO STATUS TIPO_PESSOA PROFISSAO
      EST_CIVIL REGIME_CASAMENTO NACIONAL END_TIPO ENDERECO_R END_NUMERO_RESID
      END_UNIDADE_RESID BAIRRO_R CIDADE_R UF_R CEP_R NOME_E CPF_E CELULAR_E
      EMAIL_CONJUGE ORIGEM VEICULO_CAPTACAO OBS
    ].freeze

    CDIMIM_FIELDS = %w[
      CODIGO CODIGO_I ORDEM FILE_PATH FILE_PATH_P FILE_PATH_O VER_WEB
      DESTAQUE_WEB DESCRICAO
    ].freeze

    CADCAT_FIELDS = %w[CODIGO CATEGORIA CATEGORIA_MESTRE].freeze

    Result = Struct.new(
      :dry_run,
      :scanned_properties,
      :existing_properties,
      :created_properties,
      :failed_properties,
      :created_proprietors,
      :existing_proprietors,
      :properties_with_pictures,
      :imported_picture_urls,
      :errors,
      keyword_init: true
    )

    def initialize(dump_dir: DEFAULT_DUMP_DIR, dry_run: true, limit: nil)
      dump_path = Pathname.new(dump_dir.to_s)
      @dump_dir = dump_path.absolute? ? dump_path : Rails.root.join(dump_path)
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @limit = limit.to_i.positive? ? limit.to_i : nil
      @categories = {}
      @clients = {}
      @pictures_by_code = Hash.new { |hash, key| hash[key] = [] }
      @existing_property_codes = Set.new
      @existing_development_codes = Set.new
      @existing_proprietor_codes = Set.new
      @reported_existing_proprietor_codes = Set.new
      @reported_created_proprietor_codes = Set.new
    end

    def call
      validate_dump!
      load_reference_data

      result = Result.new(
        dry_run: @dry_run,
        scanned_properties: 0,
        existing_properties: 0,
        created_properties: 0,
        failed_properties: 0,
        created_proprietors: 0,
        existing_proprietors: 0,
        properties_with_pictures: 0,
        imported_picture_urls: 0,
        errors: []
      )

      each_row(cadimo_path, "CADIMO", CADIMO_FIELDS) do |row|
        code = normalize_code(row["CODIGO"])
        next if code.blank?

        result.scanned_properties += 1
        if @existing_property_codes.include?(code)
          result.existing_properties += 1
          next
        end

        break if @limit && result.created_properties >= @limit

        import_property(row, result)
      end

      result.existing_proprietors = (@reported_existing_proprietor_codes - @reported_created_proprietor_codes).size
      result.created_proprietors = @reported_created_proprietor_codes.size
      result
    end

    private

    def tenant
      Current.tenant || raise(ArgumentError, "Tenant obrigatório para importar dump Vista")
    end

    def validate_dump!
      [cadimo_path, cadcli_path, cdimim_path, cadcat_path].each do |path|
        raise ArgumentError, "Arquivo nao encontrado: #{path}" unless File.exist?(path)
      end
    end

    def load_reference_data
      @existing_property_codes = tenant.habitations.where.not(codigo: [nil, ""]).pluck(:codigo).map { |code| code.to_s.strip }.to_set
      @existing_development_codes = tenant.habitations.empreendimentos.where.not(codigo: [nil, ""]).pluck(:codigo).map { |code| code.to_s.strip }.to_set
      @existing_proprietor_codes = tenant.proprietors.where.not(vista_code: [nil, ""]).pluck(:vista_code).map { |code| code.to_s.strip }.to_set

      each_row(cadcat_path, "CADCAT", CADCAT_FIELDS) do |row|
        code = normalize_code(row["CODIGO"])
        next if code.blank?

        @categories[code] = present_value(row["CATEGORIA"])
      end

      each_row(cadcli_path, "CADCLI", CADCLI_FIELDS) do |row|
        code = normalize_code(row["CODIGO_C"])
        next if code.blank?

        @clients[code] = row
      end

      each_row(cdimim_path, "CDIMIM", CDIMIM_FIELDS) do |row|
        code = normalize_code(row["CODIGO"])
        path = present_value(row["FILE_PATH"]) || present_value(row["FILE_PATH_O"]) || present_value(row["FILE_PATH_P"])
        next if code.blank? || path.blank?

        @pictures_by_code[code] << {
          "url" => absolute_photo_url(path),
          "url_pequena" => absolute_photo_url(present_value(row["FILE_PATH_P"]) || path),
          "principal" => yes?(row["DESTAQUE_WEB"]),
          "ordem" => integer_value(row["ORDEM"]).presence || @pictures_by_code[code].size + 1,
          "descricao" => present_value(row["DESCRICAO"])
        }.compact
      end

      @pictures_by_code.each_value do |pictures|
        pictures.sort_by! { |picture| picture["ordem"].to_i }
        pictures.first["principal"] = true if pictures.present? && pictures.none? { |picture| picture["principal"] }
      end
    end

    def import_property(row, result)
      code = normalize_code(row["CODIGO"])
      owner_code = normalize_code(row["CODIGO_C"])
      proprietor = resolve_proprietor(owner_code, result)
      pictures = @pictures_by_code[code]
      attrs = habitation_attributes(row, proprietor, pictures)

      if @dry_run
        result.created_properties += 1
        result.properties_with_pictures += 1 if pictures.present?
        result.imported_picture_urls += pictures.size
        return
      end

      Habitation.transaction do
        habitation = tenant.habitations.new(attrs)
        habitation.skip_auto_audit = true
        habitation.save!
        @existing_property_codes << code
        @existing_development_codes << code if habitation.empreendimento?
      end

      result.created_properties += 1
      result.properties_with_pictures += 1 if pictures.present?
      result.imported_picture_urls += pictures.size
    rescue StandardError => e
      result.failed_properties += 1
      result.errors << { codigo: code, erro: e.message }
    end

    def resolve_proprietor(owner_code, result)
      return nil if owner_code.blank?

      if @existing_proprietor_codes.include?(owner_code)
        @reported_existing_proprietor_codes << owner_code
        return tenant.proprietors.find_by(vista_code: owner_code) unless @dry_run

        nil
      end

      client = @clients[owner_code]
      return nil if client.blank?

      if @dry_run
        @existing_proprietor_codes << owner_code
        @reported_created_proprietor_codes << owner_code
        return nil
      end

      proprietor = tenant.proprietors.create!(proprietor_attributes(client))
      @existing_proprietor_codes << owner_code
      @reported_created_proprietor_codes << owner_code
      proprietor
    end

    def proprietor_attributes(row)
      {
        name: present_value(row["NOME"]) || "Proprietario #{row['CODIGO_C']}",
        role: :owner,
        vista_code: normalize_code(row["CODIGO_C"]),
        cpf_cnpj: present_value(row["CPF"]),
        rg_ie: present_value(row["RG"]),
        email: present_value(row["EMAIL_R"]) || present_value(row["EMAIL_C"]),
        phone_primary: present_value(row["FONE_PRINCIPAL"]),
        mobile_phone: present_value(row["CELULAR"]),
        residential_phone: present_value(row["FONE_R"]),
        business_phone: present_value(row["FONE_C"]),
        profession: present_value(row["PROFISSAO"]),
        marital_status: present_value(row["EST_CIVIL"]),
        marriage_regime: present_value(row["REGIME_CASAMENTO"]),
        nationality: present_value(row["NACIONAL"]),
        capture_vehicle: present_value(row["VEICULO_CAPTACAO"]) || present_value(row["ORIGEM"]),
        registered_at: date_value(row["DATA"]),
        notes: present_value(row["OBS"]),
        is_client: yes?(row["CLIENTE"]),
        address_type: present_value(row["END_TIPO"]),
        street: present_value(row["ENDERECO_R"]),
        number: present_value(row["END_NUMERO_RESID"]),
        complement: present_value(row["END_UNIDADE_RESID"]),
        neighborhood: present_value(row["BAIRRO_R"]),
        city: present_value(row["CIDADE_R"]),
        uf: present_value(row["UF_R"]).to_s.first(2).presence,
        cep: present_value(row["CEP_R"]),
        spouse_name: present_value(row["NOME_E"]),
        spouse_email: present_value(row["EMAIL_CONJUGE"]),
        spouse_phone: present_value(row["CELULAR_E"]),
        spouse_cpf_cnpj: present_value(row["CPF_E"])
      }
    end

    def habitation_attributes(row, proprietor, pictures)
      category = present_value(row["CATEGORIA"]) ||
                 @categories[normalize_code(row["CODIGO_CT"])] ||
                 infer_category(row) ||
                 "Apartamento"
      status = Habitation.normalize_status(present_value(row["STATUS"])) || "Pendente"
      owner_name = proprietor&.name || @clients.dig(normalize_code(row["CODIGO_C"]), "NOME")

      {
        codigo: normalize_code(row["CODIGO"]),
        categoria: category,
        status: status,
        status_vista: present_value(row["STATUS"]),
        situacao: present_value(row["SITUACAO"]),
        tipo: yes?(row["E_EMPREENDIMENTO"]) || category.casecmp("Empreendimento").zero? ? "Empreendimento" : "Unitário",
        codigo_empreendimento: existing_parent_code(row["CODIGO_EMP"]),
        nome_empreendimento: present_value(row["EMPREENDIMENTO"]),
        tipo_endereco: present_value(row["ENDERECO_TIPO"]),
        endereco: present_value(row["ENDERECO"]),
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
        dormitorios_qtd: integer_value(row["DORMITORIO"]),
        suites_qtd: integer_value(row["SUITE"]),
        banheiros_qtd: integer_value(row["BANHEIRO_SOCIAL"]),
        banheiro_social_qtd: integer_value(row["BANHEIRO_SOCIAL"]),
        vagas_qtd: integer_value(row["VAGAS"]),
        elevadores_qtd: integer_value(row["ELEVADORES"]),
        area_privativa_m2: decimal_value(row["AREA_PRIVATIVA"]),
        area_total_m2: decimal_value(row["AREA_TOTAL"]),
        area_terreno_m2: decimal_value(row["AREA_TERRENO"]),
        area_util_m2: decimal_value(row["AREA_CONSTRUIDA"]),
        valor_venda_cents: money_cents(row["VLR_VENDA"]),
        valor_locacao_cents: money_cents(row["VALOR_ALUGUEL"]) || money_cents(row["VLR_ALUGUEL"]),
        valor_condominio_cents: money_cents(row["VLR_CONDOMINIO"]),
        valor_iptu_cents: money_cents(row["VLR_IPTU"]),
        valor_total_aluguel_cents: rent_total_cents(row),
        titulo_anuncio: present_value(row["TITULO_SITE"]) || present_value(row["TITULO_WEB"]) || default_title(row, category),
        descricao_web: present_value(row["DESCRICAO_PARA_WEB"]) || present_value(row["TEXTO_ANUNCIO"]),
        descricao_interna: present_value(row["OBS"]),
        observacoes: present_value(row["OBS_VENDA"]) || present_value(row["OBS_LOCACAO"]),
        descricao_empreendimento: present_value(row["DESCRICAO_EMP"]),
        construtora: present_value(row["CONSTRUTORA"]),
        proprietor_id: proprietor&.id,
        proprietario: owner_name,
        proprietario_codigo: normalize_code(row["CODIGO_C"]),
        exibir_no_site_flag: yes?(row["EXIBIR_NO_SITE_SALUTE"]) || yes?(row["EXIBIR_NO_SIT_SALUTE"]) || yes?(row["DA_WEB"]),
        destaque_web_flag: yes?(row["DESTAQUE_WEB"]),
        lancamento_flag: yes?(row["LANCAMENTO"]),
        mobiliado_flag: yes?(row["MOBILIADO"]),
        aceita_financiamento_flag: yes?(row["ACEITA_FINANCIAMENTO"]),
        aceita_permuta_flag: yes?(row["ACEITA_PERMUTA"]),
        tem_placa_flag: yes?(row["TEM_PLACA"]),
        exclusivo_flag: yes?(row["EXCLUSIVO"]),
        data_cadastro_crm: datetime_value(row["DATA"]),
        data_atualizacao_crm: datetime_value(row["DH_ATUALIZACAO"]) || datetime_value(row["DATA_ATUALIZACAO"]),
        data_entrega: date_value(row["DATA_ENTREGA"]),
        codigo_corretor: normalize_code(row["CODIGO_M"]),
        captador_account_id: present_value(row["CAPTADOR_ACCOUNT_ID"]),
        agenciador: present_value(row["CAPTADOR_ACCOUNT_NOME"]),
        codigo_dwv: unique_dwv_code(row["CODIGO_DWV"]),
        imovel_dwv: present_value(row["IMOVEL_DWV"]) || "Nao",
        foto_classificacao: photo_classification(row),
        pictures: pictures,
        last_sync_at: Time.current,
        last_sync_status: "success",
        last_sync_message: "Importado do dump Vista #{DEFAULT_DUMP_DIR}"
      }
    end

    def infer_category(row)
      title = [row["TITULO_SITE"], row["TITULO_WEB"], row["DESCRICAO_PARA_WEB"]].map { |value| present_value(value).to_s.downcase }.join(" ")
      return "Cobertura" if title.include?("cobertura")
      return "Casa em Condomínio" if title.include?("casa em condomínio") || title.include?("casa em condominio")
      return "Casa" if title.match?(/\bcasa\b/)
      return "Terreno" if title.include?("terreno")
      return "Sala Comercial" if title.include?("sala comercial")
      return "Loja" if title.match?(/\bloja\b/)

      nil
    end

    def default_title(row, category)
      location = [present_value(row["BAIRRO"]), present_value(row["CIDADE"])].compact.join(" - ")
      [category, location.presence, "Cod. #{normalize_code(row['CODIGO'])}"].compact.join(" ")
    end

    def existing_parent_code(raw_code)
      code = normalize_code(raw_code)
      return nil if code.blank?

      @existing_development_codes.include?(code) ? code : nil
    end

    def unique_dwv_code(raw_code)
      code = normalize_code(raw_code)
      return nil if code.blank?

      tenant.habitations.where(imovel_dwv: "Sim", codigo_dwv: code).exists? ? nil : code
    end

    def photo_classification(row)
      return "Profissionais" if yes?(row["PROFISSIONAIS"])
      return "Boas" if yes?(row["BOAS"])
      return "Aceitáveis" if yes?(row["ACEITAVEIS"])
      return "Não tem fotos" if yes?(row["NAO_TEM_FOTOS"])

      nil
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

    def normalize_code(value)
      code = present_value(value)
      code.present? && code != "0" ? code : nil
    end

    def yes?(value)
      present_value(value).to_s.casecmp("sim").zero?
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

    def rent_total_cents(row)
      rent_cents = money_cents(row["VALOR_ALUGUEL"]) || money_cents(row["VLR_ALUGUEL"])
      return 0 unless rent_cents.to_i.positive?

      money_cents(row["VLR_TOTAL_ALUGUEL"]) || rent_cents
    end

    def date_value(value)
      raw = present_value(value)
      return nil if raw.blank? || raw == "0000-00-00"

      Date.parse(raw)
    rescue ArgumentError
      nil
    end

    def datetime_value(value)
      raw = present_value(value)
      return nil if raw.blank? || raw.start_with?("0000-00-00")

      Time.zone.parse(raw)
    rescue ArgumentError
      nil
    end

    def absolute_photo_url(path)
      return nil if path.blank?
      return path if path.start_with?("http://", "https://")

      PHOTO_BASE_URL + path
    end

    def cadimo_path = @dump_dir.join("CADIMO.sql")
    def cadcli_path = @dump_dir.join("CADCLI.sql")
    def cdimim_path = @dump_dir.join("CDIMIM.sql")
    def cadcat_path = @dump_dir.join("CADCAT.sql")
  end
end

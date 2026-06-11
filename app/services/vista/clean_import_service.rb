module Vista
  class CleanImportService
    DEFAULT_PASSWORD = "salute123456"
    PHOTO_BASE_URL = "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/".freeze

    Result = Struct.new(:batch_id, :dry_run, :stats, :errors, keyword_init: true)

    def initialize(batch: VistaImportBatch.latest_first.first, dry_run: true, reset: false)
      @batch = batch
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @reset = ActiveModel::Type::Boolean.new.cast(reset)
      @stats = Hash.new(0)
      @errors = []
    end

    def call
      raise ArgumentError, "Nenhum batch Vista raw encontrado" unless @batch

      reset_targets! if @reset && !@dry_run
      load_categories
      load_owner_codes

      import_admin_users
      import_contacts
      import_proprietors
      load_reference_ids
      import_habitations
      load_reference_ids
      backfill_development_links
      load_reference_ids
      import_broker_assignments

      Result.new(batch_id: @batch.id, dry_run: @dry_run, stats: @stats, errors: @errors)
    end

    private

    def reset_targets!
      HabitationBrokerAssignment.delete_all
      Habitation.delete_all
      Proprietor.delete_all
      AdminUser.where.not(email: admin_email).delete_all
    end

    def admin_email
      ENV.fetch("ADMIN_EMAIL", "admin@saluteimoveis.com.br")
    end

    def load_categories
      @categories = {}
      raw("CADCAT").find_each do |record|
        code = code(record.payload["CODIGO"])
        @categories[code] = value(record.payload["CATEGORIA"]) if code
      end
    end

    def load_reference_ids
      @admin_user_id_by_vista_id = AdminUser.where.not(vista_id: [nil, ""]).pluck(:vista_id, :id).to_h
      @crm_contact_id_by_vista_code = CrmContact.where.not(vista_code: [nil, ""]).pluck(:vista_code, :id).to_h
      @proprietor_id_by_vista_code = Proprietor.where.not(vista_code: [nil, ""]).pluck(:vista_code, :id).to_h
      @habitation_id_by_codigo = Habitation.where.not(codigo: [nil, ""]).pluck(:codigo, :id).to_h
      @development_codes = Habitation.where(tipo: "Empreendimento").where.not(codigo: [nil, ""]).pluck(:codigo).to_set
    end

    def load_owner_codes
      @owner_codes_from_habitations = raw("CADIMO")
        .reorder(nil)
        .where("coalesce(nullif(payload->>'CODIGO_C', ''), '0') <> '0'")
        .distinct
        .pluck(Arel.sql("payload->>'CODIGO_C'"))
        .to_set
    end

    def raw(table)
      @batch.vista_raw_records.where(table_name: table).order(:id)
    end

    def import_admin_users
      default_profile = profile_for("Corretor")

      raw("CADEMP").find_each do |record|
        row = record.payload
        vista_id = code(row["CODIGO_D"])
        next unless vista_id

        attrs = {
          vista_id: vista_id,
          email: email_for_agent(row, vista_id),
          name: value(row["NOME_COMPLETO"]) || value(row["NOME"]) || "Corretor #{vista_id}",
          creci: value(row["CRECI"]),
          phone: value(row["CELULAR"]) || value(row["FONE"]),
          biography: value(row["OBS"]),
          birth_date: date(row["NASCIMENTO"]),
          city: value(row["CIDADE"]),
          vista_agenciador: yes?(row["AGENCIADOR"]),
          source_created_on: date(row["DATA"]),
          source_departed_on: date(row["DATA_SAIDA"]),
          last_login_at: datetime(row["ULTIMO_LOGIN"]),
          source_photo_path: value(row["FOTO"]),
          cpf_cnpj: value(row["CPF"]),
          rg_ie: value(row["RG"]),
          nationality: value(row["NACIONAL"]),
          gender: value(row["SEXO"]),
          marital_status: value(row["EST_CIVIL"]),
          address_type: value(row["ENDERECO_TIPO"]),
          street: value(row["ENDERECO"]),
          number: value(row["NUM_ENDERECO"]),
          complement: value(row["COMP_ENDERECO"]),
          neighborhood: value(row["BAIRRO"]),
          secondary_phone: value(row["CELULAR2"]),
          team_code: code(row["CODIGO_EQU"]),
          capture_goal: integer(row["META_CAPTACOES"]),
          rental_capture_goal: integer(row["META_CAPTACOES_LOC"]),
          sales_goal_cents: money_cents(row["META_VLR_VENDAS"]),
          role: role_for_agent(row),
          profile: profile_for_agent(row) || default_profile,
          active: !yes?(row["INATIVO"]) && !yes?(row["EXCLUIDO"]),
          display_on_site: yes?(row["VER_WEB"]) || yes?(row["CORRETOR"]),
          acting_type: acting_type(row),
          vista_import_batch_id: @batch.id,
          vista_payload: row
        }

        if @dry_run
          @stats[:admin_users_read] += 1
          next
        end

        user = AdminUser.find_by(vista_id: vista_id) || AdminUser.find_or_initialize_by(email: attrs[:email])
        user.assign_attributes(attrs)
        user.password = DEFAULT_PASSWORD if user.encrypted_password.blank?
        user.save!
        @stats[:admin_users_imported] += 1
      rescue StandardError => e
        track_error(:admin_users, vista_id, e)
      end
    end

    def import_proprietors
      raw("CADCLI").find_each do |record|
        row = record.payload
        vista_code = code(row["CODIGO_C"])
        next unless vista_code
        next unless owner_contact?(row, vista_code)

        attrs = {
          name: value(row["NOME"]) || "Cliente #{vista_code}",
          role: proprietor_role(row),
          vista_code: vista_code,
          cpf_cnpj: value(row["CPF"]),
          rg_ie: value(row["RG"]),
          issuing_authority: value(row["RG_EM"]),
          birth_date: date(row["DT_NASCIMENTO"]) || date(row["NASCIMENTO"]),
          email: value(row["EMAIL_R"]) || value(row["EMAIL_C"]),
          phone_primary: value(row["FONE_PRINCIPAL"]),
          mobile_phone: value(row["CELULAR"]),
          residential_phone: value(row["FONE_R"]),
          business_phone: value(row["FONE_C"]),
          phone_extension: value(row["FONE_RAMAL"]),
          profession: value(row["PROFISSAO"]),
          marital_status: value(row["EST_CIVIL"]),
          marriage_regime: value(row["REGIME_CASAMENTO"]),
          nationality: value(row["NACIONAL"]),
          capture_vehicle: value(row["VEICULO_CAPTACAO"]) || value(row["ORIGEM"]),
          registered_at: datetime(row["DATA"]),
          source_status: value(row["STATUS"]),
          source_updated_at: datetime(row["DATA_H"]),
          potential_value_cents: money_cents(row["VALOR_POTENCIAL"]),
          favorite: yes?(row["CLIENTE_FAVORITO"]),
          restricted: yes?(row["PROP_RESTRITO"]),
          receive_information: yes?(row["RECEBER_INFORMACOES"]),
          show_email_to_client: yes?(row["EXIBIR_EMAIL_CLIENTE"]),
          show_phone_on_web: yes?(row["EXIBIR_FONE_WEB"]),
          notes: [value(row["OBS"]), value(row["OBSERVACOESPROP"])].compact.join("\n\n").presence,
          is_client: yes?(row["CLIENTE"]),
          address_type: value(row["END_TIPO"]),
          street: value(row["ENDERECO_R"]),
          number: value(row["END_NUMERO_RESID"]),
          complement: value(row["END_UNIDADE_RESID"]),
          block: value(row["END_BLOCO_RESID"]),
          neighborhood: value(row["BAIRRO_R"]),
          city: value(row["CIDADE_R"]),
          uf: value(row["UF_R"]).to_s.first(2).presence,
          cep: value(row["CEP_R"]),
          spouse_name: value(row["NOME_E"]),
          spouse_email: value(row["EMAIL_CONJUGE"]),
          spouse_phone: value(row["CELULAR_E"]),
          spouse_cpf_cnpj: value(row["CPF_E"]),
          spouse_birth_date: date(row["DT_NASCIMENTO_CONJUGE"]),
          vista_import_batch_id: @batch.id,
          vista_payload: row
        }

        if @dry_run
          @stats[:proprietors_read] += 1
          next
        end

        proprietor = Proprietor.find_or_initialize_by(vista_code: vista_code)
        proprietor.assign_attributes(attrs)
        proprietor.save!
        @stats[:proprietors_imported] += 1
      rescue StandardError => e
        track_error(:proprietors, vista_code, e)
      end

      sanitize_non_owner_proprietors unless @dry_run
    end

    def import_contacts
      raw("CADCLI").find_each do |record|
        row = record.payload
        vista_code = code(row["CODIGO_C"])
        next unless vista_code

        attrs = {
          vista_import_batch_id: @batch.id,
          vista_code: vista_code,
          name: value(row["NOME"]) || "Contato #{vista_code}",
          email: value(row["EMAIL_R"]) || value(row["EMAIL_C"]),
          phone_primary: value(row["FONE_PRINCIPAL"]),
          mobile_phone: value(row["CELULAR"]),
          residential_phone: value(row["FONE_R"]),
          business_phone: value(row["FONE_C"]),
          cpf_cnpj: value(row["CPF"]),
          rg_ie: value(row["RG"]),
          contact_type: contact_type(row, vista_code),
          is_client: yes?(row["CLIENTE"]),
          is_owner: yes?(row["PROPRIETARIO"]),
          is_buyer: yes?(row["COMPRADOR"]),
          is_referenced_owner: @owner_codes_from_habitations.include?(vista_code),
          capture_vehicle: value(row["VEICULO_CAPTACAO"]) || value(row["ORIGEM"]),
          registered_at: datetime(row["DATA"]),
          source_status: value(row["STATUS"]),
          source_updated_at: datetime(row["DATA_H"]),
          potential_value_cents: money_cents(row["VALOR_POTENCIAL"]),
          favorite: yes?(row["CLIENTE_FAVORITO"]),
          restricted: yes?(row["PROP_RESTRITO"]),
          receive_information: yes?(row["RECEBER_INFORMACOES"]),
          show_email_to_client: yes?(row["EXIBIR_EMAIL_CLIENTE"]),
          show_phone_on_web: yes?(row["EXIBIR_FONE_WEB"]),
          notes: [value(row["OBS"]), value(row["OBSERVACOESPROP"])].compact.join("\n\n").presence,
          metadata: row
        }

        if @dry_run
          @stats[:contacts_read] += 1
          next
        end

        contact = CrmContact.find_or_initialize_by(vista_code: vista_code)
        contact.assign_attributes(attrs)
        contact.save!
        @stats[:contacts_imported] += 1
      rescue StandardError => e
        track_error(:contacts, vista_code, e)
      end
    end

    def import_habitations
      photo_urls_by_code = photo_urls_by_code()
      video_urls_by_code = video_urls_by_code()

      raw("CADIMO").find_each do |record|
        row = record.payload
        codigo = code(row["CODIGO"])
        next unless codigo

        attrs = habitation_attrs(row, photo_urls_by_code[codigo], video_urls_by_code[codigo])

        if @dry_run
          @stats[:habitations_read] += 1
          next
        end

        habitation = Habitation.find_or_initialize_by(codigo: codigo)
        habitation.skip_auto_audit = true if habitation.respond_to?(:skip_auto_audit=)
        habitation.assign_attributes(attrs)
        habitation.save!
        upsert_address(habitation, row)
        @stats[:habitations_imported] += 1
      rescue StandardError => e
        track_error(:habitations, codigo, e)
      end
    end

    def backfill_development_links
      raw("CADIMO").find_each do |record|
        row = record.payload
        codigo = code(row["CODIGO"])
        next unless codigo
        next if development_row?(row)

        development_code = development_code_for(row)
        unless development_code
          @stats[:development_links_unmatched] += 1 if value(row["EMPREENDIMENTO"]).present? || code(row["CODIGO_EMP"]).present?
          next
        end

        if @dry_run
          @stats[:development_links_read] += 1
          next
        end

        updated = Habitation
          .where(codigo: codigo)
          .where("tipo IS DISTINCT FROM ?", "Empreendimento")
          .where(codigo_empreendimento: [nil, ""])
          .update_all(codigo_empreendimento: development_code, updated_at: Time.current)

        @stats[:development_links_imported] += updated
      rescue StandardError => e
        track_error(:development_links, codigo || record.id, e)
      end
    end

    def import_broker_assignments
      HabitationBrokerAssignment.where(vista_import_batch_id: @batch.id).delete_all unless @dry_run

      raw("CDIMAG").find_each do |record|
        row = record.payload
        habitation_id = @habitation_id_by_codigo[code(row["CODIGO_O"])]
        admin_user_id = @admin_user_id_by_vista_id[code(row["CODIGO_D"])]

        unless habitation_id && admin_user_id
          @stats[:broker_assignments_skipped] += 1
          next
        end

        attrs = {
          habitation_id: habitation_id,
          admin_user_id: admin_user_id,
          role: broker_assignment_role(row),
          commission_type: broker_commission_type(row),
          commission_value: broker_commission_value(row),
          observations: value(row["TIPO"]),
          source_created_at: datetime(row["DATA"]),
          sale_commission_percentage: decimal(row["PRCNT_VN"]),
          rental_commission_percentage: decimal(row["PRCNT_LC"]),
          rental_cancellation_commission_percentage: decimal(row["PRCNT_LCAN"]),
          sale_commission_cents: money_cents(row["VALOR_VN"]),
          rental_commission_cents: money_cents(row["VALOR_LC"]),
          rental_cancellation_commission_cents: money_cents(row["VALOR_LCAN"]),
          vista_source_key: value(row["NUMERO"]) || record.id.to_s,
          vista_import_batch_id: @batch.id,
          vista_payload: row
        }

        if @dry_run
          @stats[:broker_assignments_read] += 1
          next
        end

        assignment = HabitationBrokerAssignment.find_or_initialize_by(vista_import_batch_id: @batch.id, vista_source_key: attrs[:vista_source_key])
        assignment.assign_attributes(attrs)
        assignment.save!
        @stats[:broker_assignments_imported] += 1
      rescue StandardError => e
        track_error(:broker_assignments, record.id, e)
      end
    end

    def habitation_attrs(row, pictures, videos)
      owner_code = code(row["CODIGO_C"])
      broker_code = code(row["CODIGO_M"])
      category = value(row["CATEGORIA"]) || @categories[code(row["CODIGO_CT"])] || infer_category(row) || "Apartamento"
      status = Habitation.normalize_status(value(row["STATUS"])) || "Pendente"

      {
        codigo: code(row["CODIGO"]),
        categoria: category,
        status: status,
        status_vista: value(row["STATUS"]),
        situacao: value(row["SITUACAO"]),
        tipo: development_row?(row, category) ? "Empreendimento" : "Unitário",
        codigo_empreendimento: development_code_for(row),
        nome_empreendimento: value(row["EMPREENDIMENTO"]),
        tipo_endereco: value(row["ENDERECO_TIPO"]),
        endereco: value(row["ENDERECO"]),
        numero: value(row["NUM_ENDERECO"]),
        complemento: value(row["COMP_ENDERECO"]),
        bairro: value(row["BAIRRO"]),
        bairro_comercial: value(row["BAIRRO_COMERCIAL"]),
        cidade: value(row["CIDADE"]),
        uf: value(row["UF"]).to_s.first(2).presence || "SC",
        cep: value(row["CEP"]),
        pais: value(row["PAIS"]) || "Brasil",
        latitude: decimal(row["GMAPS_LAT"]),
        longitude: decimal(row["GMAPS_LNG"]),
        dormitorios_qtd: integer(row["DORMITORIO"]),
        suites_qtd: integer(row["SUITE"]),
        banheiros_qtd: integer(row["BANHEIRO_SOCIAL"]) || integer(row["BANHO_SOCIAL"]),
        banheiro_social_qtd: integer(row["BANHEIRO_SOCIAL"]) || integer(row["BANHO_SOCIAL"]),
        vagas_qtd: integer(row["VAGAS"]),
        elevadores_qtd: integer(row["ELEVADORES"]),
        area_privativa_m2: decimal(row["AREA_PRIVATIVA"]),
        area_total_m2: decimal(row["AREA_TOTAL"]),
        area_terreno_m2: decimal(row["AREA_TERRENO"]),
        area_util_m2: decimal(row["AREA_CONSTRUIDA"]),
        valor_venda_cents: money_cents(row["VLR_VENDA"]) || money_cents(row["VENDA"]),
        valor_locacao_cents: money_cents(row["VALOR_ALUGUEL"]) || money_cents(row["VLR_ALUGUEL"]),
        valor_condominio_cents: money_cents(row["VLR_CONDOMINIO"]),
        valor_iptu_cents: money_cents(row["VLR_IPTU"]),
        valor_total_aluguel_cents: rent_total_cents(row),
        valor_promocional_cents: money_cents(row["VALOR_PROMOCIONAL"]),
        valor_venda_anterior_cents: money_cents(row["VENDA_ANTERIOR"]),
        valor_locacao_anterior_cents: money_cents(row["ALUGUEL_ANTERIOR"]),
        saldo_devedor_cents: money_cents(row["SALDO_DEVEDOR"]),
        titulo_anuncio: value(row["TITULO_SITE"]) || value(row["TITULO_WEB"]) || default_title(row, category),
        descricao_web: value(row["DESCRICAO_PARA_WEB"]) || value(row["TEXTO_ANUNCIO"]),
        descricao_interna: value(row["OBS"]),
        observacoes: value(row["OBS_VENDA"]) || value(row["OBS_LOCACAO"]),
        descricao_empreendimento: value(row["DESCRICAO_EMP"]),
        construtora: value(row["CONSTRUTORA"]),
        constructor_id: nil,
        proprietor_id: @proprietor_id_by_vista_code[owner_code],
        proprietario: value(row["SR_PROPRIETARIO"]),
        proprietario_codigo: owner_code,
        exibir_no_site_flag: yes?(row["EXIBIR_NO_SITE_SALUTE"]) || yes?(row["EXIBIR_NO_SIT_SALUTE"]) || yes?(row["DA_WEB"]),
        exibir_no_site_salute_flag: yes?(row["EXIBIR_NO_SITE_SALUTE"]) || yes?(row["EXIBIR_NO_SIT_SALUTE"]),
        destaque_web_flag: yes?(row["DESTAQUE_WEB"]),
        lancamento_flag: yes?(row["LANCAMENTO"]),
        mobiliado_flag: yes?(row["MOBILIADO"]),
        aceita_financiamento_flag: yes?(row["ACEITA_FINANCIAMENTO"]),
        aceita_permuta_flag: yes?(row["ACEITA_PERMUTA"]),
        tem_placa_flag: yes?(row["TEM_PLACA"]),
        exclusivo_flag: yes?(row["EXCLUSIVO"]),
        piscina_flag: feature_yes?(row, "PISCINA_COLETIVA", "PISCINA_AQUECIDA", "PISCINA_INFANTIL"),
        lavabo_flag: yes?(row["LIVING_LAVABO"]),
        garden_flag: yes?(row["GARDEN"]),
        quadra_mar_flag: yes?(row["QUADRA_MAR"]),
        sem_mobilia_flag: yes?(row["SEM_MOBILIA"]),
        data_cadastro_crm: datetime(row["DATA"]),
        data_atualizacao_crm: datetime(row["DH_ATUALIZACAO"]) || datetime(row["DATA_ATUALIZACAO"]),
        data_entrega: date(row["DATA_ENTREGA"]),
        codigo_corretor: broker_code,
        admin_user_id: @admin_user_id_by_vista_id[broker_code],
        captador_account_id: value(row["CAPTADOR_ACCOUNT_ID"]),
        agenciador: value(row["CAPTADOR_ACCOUNT_NOME"]),
        codigo_dwv: unique_dwv_code(row),
        imovel_dwv: value(row["IMOVEL_DWV"]) || "Nao",
        caracteristicas: characteristics(row).index_by(&:itself),
        infra_estrutura: infrastructure(row),
        destaque_localizacao: location_highlights(row).index_by(&:itself),
        caracteristica_unica: split_list(row["CARACTERISTICA_UNICA"]),
        tour_virtual: value(row["TOURVIRTUAL"]) || value(row["LINK_VIDEO"]) || value(row["ID_VIDEOW"]),
        videos: ([value(row["LINK_VIDEO"]), value(row["ID_VIDEOW"])].compact + Array(videos)).uniq,
        pictures: pictures || [],
        face: value(row["FACE"]),
        perfil_construcao: value(row["PADRAO_CONSTRUCAO"]),
        tipo_vaga: value(row["GARAGEM_TIPO"]),
        hidromassagem_qtd: integer(row["HIDRO"]) || integer(row["HIDRO_SUITE"]),
        ocupacao_status: value(row["OCUPACAO"]),
        estado_conservacao: value(row["ESTADO"]),
        andar: integer(row["N_ANDAR"]) || integer(row["ANDAR_APTO"]),
        ano_construcao: integer(row["ANO_CONSTRUCAO"]),
        demi_suites_qtd: integer(row["DEMI_SUITE"]),
        numero_box: value(row["GARAGEM_NUMERO_BOX"]),
        dimensoes_terreno: value(row["DIMENSOES_TERRENO"]),
        topografia: value(row["TOPOGRAFIA"]),
        foto_classificacao: photo_classification(row),
        podcast_url: value(row["LINKPODCAST"]),
        captador_commission_percentage: commission_percentage(row["COMISSAO_CAPTADOR"], row["PERCENTUAL_COMISSAO"]),
        broker_commission_percentage: decimal(row["COMISSAO_CORRETOR"]),
        valor_comissao_cents: commission_amount_cents(row),
        valor_livre_proprietario_cents: money_cents(row["VLR_LIVRE_PROPRIETARIO"]),
        salute_rental_management_flag: rental_management_flag(row),
        key_location: key_location(row),
        key_location_notes: value(row["CHAVE"]),
        valor_aceito_permuta_cents: money_cents(row["AC_PERMUTA_VALOR"]),
        aceita_permuta_veiculo_flag: yes?(row["ACEITA_PERMUTA_AUTO"]),
        aceita_permuta_imovel_flag: value(row["AC_PERMUTA_TIPO_IMO"]).present?,
        aceita_permuta_outros_flag: yes?(row["ACEITA_PERMUTA_OUTROS"]),
        tipo_veiculo_aceito_permuta: value(row["AC_PERMUTA_TIPO_AUT"]),
        ano_minimo_veiculo_aceito_permuta: integer(row["ANO_MIN_VEICULO_PERMUTA"]),
        permuta_valor_cents: money_cents(row["AC_PERMUTA_VALOR"]),
        permuta_localizacao: value(row["AC_PERMUTA_LOCALIZACAO"]),
        permuta_dormitorios_qtd: integer(row["AC_PERMUTA_QNT_DORMITORIOS"]),
        permuta_suites_qtd: integer(row["AC_PERMUTA_QNT_SUITES"]),
        permuta_garagens_qtd: integer(row["AC_PERMUTA_QNT_GARAGENS"]),
        matricula_imovel: value(row["MATRICULA"]),
        zona: value(row["ZONA"]),
        aceita_doacao_flag: yes?(row["ACEITA_DACAO"]),
        condicoes_negociacao: value(row["INFO_VENDA"]),
        numero_prestacoes: integer(row["PRESTACAO"]),
        responsavel_reserva: value(row["RESPONSAVEL_RESERVA"]),
        zelador_nome: value(row["ZELADOR_NOME"]),
        zelador_telefone: value(row["ZELADOR_TELEFONE"]),
        observacoes_visitas: value(row["VISITA"]) || value(row["VISITA_ACOMPANHADA"]),
        regiao_foco: value(row["IMO_REGIAO_FOCO"]),
        tipo_fachada: value(row["FACHADA"]),
        andares_qtd: integer(row["PAVIMENTOS"]),
        publicar_zapimoveis: value(row["TIPO_OFERTA_ZAP"]).present?,
        publicar_viva_real_vrsync: value(row["TIPO_PUBLICACAO_VIVA_REAL"]).present?,
        publicar_imovelweb: value(row["TIPO_PUBLICACAO_IMOVELWEB"]).present? || value(row["MODELO_IMOVELWEB"]).present?,
        publicar_chaves_na_mao: value(row["DESTAQUE_CHAVES_NA_MAO"]).present? || value(row["CHAVES_NA_MAO_PERIODO_LOCACAO"]).present?,
        publicar_casa_mineira: value(row["MODELO_CASA_MINEIRA"]).present?,
        publicar_loft: value(row["TIPO_PUBLICACAO_LOFT"]).present?,
        destaque_chaves_na_mao: yes_no(row["DESTAQUE_CHAVES_NA_MAO"]),
        periodo_locacao_chaves_na_mao: value(row["CHAVES_NA_MAO_PERIODO_LOCACAO"]),
        modelo_casa_mineira: value(row["MODELO_CASA_MINEIRA"]),
        tipo_publicacao_viva_real: value(row["TIPO_PUBLICACAO_VIVA_REAL"]),
        divulgar_endereco_viva_real: value(row["DIVULGAR_ENDERECO_VIVA_REAL"]),
        tipo_publicacao_imovelweb: value(row["TIPO_PUBLICACAO_IMOVELWEB"]) || value(row["MODELO_IMOVELWEB"]),
        mostrar_mapa_imovelweb: value(row["MOSTRAR_MAPA"]),
        last_sync_at: Time.current,
        last_sync_status: "success",
        last_sync_message: "Importado do raw Vista batch #{@batch.id}",
        vista_import_batch_id: @batch.id,
        vista_payload: row
      }.merge(location_flag_attrs(row)).compact
    end

    def upsert_address(habitation, row)
      attrs = {
        tipo_endereco: value(row["ENDERECO_TIPO"]),
        logradouro: value(row["ENDERECO"]),
        numero: value(row["NUM_ENDERECO"]),
        complemento: value(row["COMP_ENDERECO"]),
        bairro: value(row["BAIRRO"]),
        bairro_comercial: value(row["BAIRRO_COMERCIAL"]),
        cidade: value(row["CIDADE"]),
        uf: value(row["UF"]).to_s.first(2).presence || "SC",
        cep: value(row["CEP"]),
        pais: value(row["PAIS"]) || "Brasil",
        latitude: decimal(row["GMAPS_LAT"]),
        longitude: decimal(row["GMAPS_LNG"]),
        imediacoes: split_list(row["IMEDIACOES"])
      }.compact
      return unless attrs[:logradouro].present? && attrs[:cidade].present?

      address = habitation.address || habitation.build_address
      address.assign_attributes(attrs)
      address.save!
    end

    def photo_urls_by_code
      VistaFileAsset.where(vista_import_batch_id: @batch.id, kind: "property_photo").order(:codigo_imovel, :position, :id).each_with_object({}) do |asset, memo|
        next if asset.codigo_imovel.blank?

        memo[asset.codigo_imovel] ||= []
        memo[asset.codigo_imovel] << {
          "url" => asset.source_url,
          "ordem" => asset.position || memo[asset.codigo_imovel].size + 1,
          "principal" => memo[asset.codigo_imovel].empty?,
          "descricao" => value(asset.metadata["DESCRICAO"])
        }.compact
      end
    end

    def video_urls_by_code
      raw("CDIMVD").order(:id).each_with_object({}) do |record, memo|
        row = record.payload
        next unless value(row["TIPO"]).to_s.downcase == "youtube"

        codigo = code(row["CODIGO"])
        youtube_id = value(row["FILE_PATH"])
        next if codigo.blank? || youtube_id.blank?

        memo[codigo] ||= []
        memo[codigo] << "https://www.youtube.com/watch?v=#{youtube_id}"
      end
    end

    def profile_for_agent(row)
      name = if yes?(row["DIRETOR"])
               "Diretor"
             elsif yes?(row["GERENTE"])
               "Gerente"
             elsif yes?(row["CADUSU"])
               "Administrativo"
             elsif yes?(row["CORRETOR"])
               "Corretor"
             end
      profile_for(name) if name
    end

    def profile_for(name)
      return if name.blank?

      Profile.where("LOWER(name) = ?", name.downcase).first_or_create!(name: name, permissions: {}, active: true)
    end

    def email_for_agent(row, vista_id)
      email = value(row["EMAIL"])
      if email&.match?(URI::MailTo::EMAIL_REGEXP)
        existing = AdminUser.where(email: email).where.not(vista_id: [nil, vista_id]).exists?
        return email unless existing
      end

      "corretor#{vista_id}@saluteimoveis.local"
    end

    def role_for_agent(row)
      yes?(row["DIRETOR"]) || yes?(row["GERENTE"]) ? "admin" : "editor"
    end

    def acting_type(row)
      sale = yes?(row["ATUACAO_VENDA"])
      rent = yes?(row["ATUACAO_LOCACAO"])
      return "both" if sale && rent
      return "sales" if sale
      return "rentals" if rent

      "both"
    end

    def proprietor_role(row)
      return "broker" if yes?(row["CORRETOR"])
      return "developer" if yes?(row["CONSTRUTOR_VENDEDOR"])

      "owner"
    end

    def owner_contact?(row, vista_code)
      yes?(row["PROPRIETARIO"]) || @owner_codes_from_habitations.include?(vista_code)
    end

    def contact_type(row, vista_code)
      return "owner" if owner_contact?(row, vista_code)
      return "buyer" if yes?(row["COMPRADOR"])
      return "client" if yes?(row["CLIENTE"])

      "contact"
    end

    def sanitize_non_owner_proprietors
      valid_codes = @owner_codes_from_habitations.to_a
      valid_codes += raw("CADCLI")
        .where("payload->>'PROPRIETARIO' IN (?)", ["Sim", "sim", "S", "1", "true", "True"])
        .pluck(Arel.sql("payload->>'CODIGO_C'"))
      valid_codes = valid_codes.compact.uniq

      invalid_scope = Proprietor.where(vista_import_batch_id: @batch.id).where.not(vista_code: valid_codes)
      invalid_ids = invalid_scope.pluck(:id)
      return if invalid_ids.empty?

      [ClientInteraction, HabitationInteraction, CrmAppointment, ClientPropertyInterest].each do |model|
        model.where(proprietor_id: invalid_ids).update_all(proprietor_id: nil)
      end
      invalid_scope.delete_all
      @stats[:proprietors_sanitized_removed] = invalid_ids.size
    end

    def existing_development_code(raw)
      candidate = code(raw)
      candidate if candidate && @development_codes.include?(candidate)
    end

    def development_code_for(row)
      existing_development_code(row["CODIGO_EMP"])
    end

    def development_row?(row, category = nil)
      yes?(row["E_EMPREENDIMENTO"]) || (category || value(row["CATEGORIA"])).to_s.casecmp("Empreendimento").zero?
    end

    def unique_dwv_code(row)
      candidate = code(row["CODIGO_DWV"])
      return unless candidate

      duplicate = Habitation.where(imovel_dwv: "Sim", codigo_dwv: candidate).where.not(codigo: code(row["CODIGO"])).exists?
      candidate unless duplicate
    end

    def broker_assignment_role(row)
      type = value(row["TIPO"]).to_s.downcase
      return "captador" if type.include?("capt")
      return "placa" if type.include?("plac")

      "promotor"
    end

    def broker_commission_type(row)
      value(row["TIPO_COMISSAO"]).to_s.downcase.include?("pre") ? "fixed" : "percentage"
    end

    def broker_commission_value(row)
      decimal(row["COMISSAO"]) || decimal(row["PRCNT_VN"]) || decimal(row["VALOR_VN"])
    end

    def infer_category(row)
      text = [row["TITULO_SITE"], row["TITULO_WEB"], row["DESCRICAO_PARA_WEB"]].map { |raw| value(raw).to_s.downcase }.join(" ")
      return "Cobertura" if text.include?("cobertura")
      return "Casa em Condomínio" if text.include?("casa em condomínio") || text.include?("casa em condominio")
      return "Casa" if text.match?(/\bcasa\b/)
      return "Terreno" if text.include?("terreno")
      return "Sala Comercial" if text.include?("sala comercial")
      return "Loja" if text.match?(/\bloja\b/)
    end

    def default_title(row, category)
      [category, value(row["BAIRRO"]), "Cod. #{code(row['CODIGO'])}"].compact.join(" ")
    end

    CHARACTERISTIC_FIELDS = %w[
      ADEGA AGUA_QUENTE ALARME AQUECIMENTO_CENTRAL AQUECIMENTO_ELETRICO AR_CENTRAL
      AR_CONDICIONADO AREA_SERVICO ARMARIOS_EMBUTIDOS BANHO_AUXILIAR BANHO_SOCIAL
      BANHEIRO_SOCIAL CHURRASQUEIRA_A_CARVAO CHURRASQUEIRA_A_GAS CLOSET COPA
      COPA_COZINHA COZINHA COZINHA_AMERICANA COZINHA_PLANEJADA DEPENDENCIA
      DEPOSITO DESPENSA DORMITORIO_ARMARIO ENTRADA_SERVICO GABINETE HIDRO
      HIDRO_SUITE HOME_THEATER LIVING_LAREIRA LIVING_LAVABO SACADA_ABERTA
      SACADA_FECHADA SACADA_INTEGRADA SALA_JANTAR SALA_TV SPLIT VARANDA VARANDAS
      WC_EMPREGADA MOBILIADO DECORADO GARDEN QUADRA_MAR SEM_MOBILIA VISTA_MAR
      VISTA_FRENTE_MAR
    ].freeze

    INFRASTRUCTURE_FIELDS = %w[
      BICICLETARIO CIRCUITO_INTERNO_TV ELEVADOR_COM ELEVADOR_SERVICO ESPACO_GOURMET
      ESTACIONAMENTO GAS_CENTRAL GERADOR_ENERGIA INTERFONE JARDIM PISCINA_AQUECIDA
      PISCINA_COLETIVA PISCINA_INFANTIL PLAYGROUD POCO_ARTESIANO PORTARIA
      PORTARIA_24HS PORTARIA_ED QUADRA_ESPORTES QUADRA_POLIESPORTIVA QUADRA_TENIS
      QUIOSQUE SALA_GINASTICA SALA_JOGOS SALAO_FESTAS SALAO_BRINQUEDOS SAUNA
      SAUNA_COL SEGURANCA TERRACO_COL VIGILANCIA_24H
    ].freeze

    LOCATION_FLAGS = {
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

    def characteristics(row)
      labels_for(row, CHARACTERISTIC_FIELDS, category: "feature")
    end

    def infrastructure(row)
      labels_for(row, INFRASTRUCTURE_FIELDS, category: "infrastructure")
    end

    def location_highlights(row)
      labels_for(row, LOCATION_FLAGS.keys, category: "feature")
    end

    def labels_for(row, fields, category:)
      fields.filter_map do |field|
        next unless yes?(row[field])

        AttributeOptions::HabitationFeatureNormalizer.label(field == "PLAYGROUD" ? "PLAYGROUND" : field, category: category)
      end.uniq
    rescue NameError
      fields.select { |field| yes?(row[field]) }.map { |field| field.humanize }
    end

    def location_flag_attrs(row)
      LOCATION_FLAGS.each_with_object({}) do |(field, attr), attrs|
        attrs[attr] = true if yes?(row[field])
      end
    end

    def feature_yes?(row, *fields)
      fields.any? { |field| yes?(row[field]) }
    end

    def photo_classification(row)
      return "Profissionais" if yes?(row["PROFISSIONAIS"])
      return "Boas" if yes?(row["BOAS"])
      return "Aceitáveis" if yes?(row["ACEITAVEIS"])
      return "Não tem fotos" if yes?(row["NAO_TEM_FOTOS"])
    end

    def key_location(row)
      return "Imobiliária" if yes?(row["CHAVES_NA_AGENCIA"])
      return "Corretor(a)" if value(row["CHAVE"]).to_s.downcase.include?("corret")
      return "Proprietário" if value(row["CHAVE"]).to_s.downcase.include?("propriet")

      nil
    end

    def split_list(raw)
      value(raw).to_s.split(/[,\n;]+/).map(&:strip).reject(&:blank?).uniq
    end

    def code(raw)
      text = value(raw)
      return if text.blank? || text == "0"

      text
    end

    def value(raw)
      return if raw.nil?

      text = Vista::TextEncodingNormalizer.normalize(raw.to_s).strip
      return if text.blank? || text == "NULL" || text == "\\N"

      text
    end

    def yes?(raw)
      value(raw).to_s.downcase.in?(%w[sim yes true 1 s])
    end

    def yes_no(raw)
      return "sim" if yes?(raw)
      return "nao" if value(raw).present?

      nil
    end

    def commission_percentage(primary_raw, fallback_raw = nil)
      primary = decimal(primary_raw)
      fallback = decimal(fallback_raw)
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
      %w[OBS_VENDA OBS_LOCACAO OBSERVACOES INFO_VENDA TEXTO_ANUNCIO DESCRICAO_WEB].filter_map { |field| value(row[field]) }
    end

    def integer(raw)
      value(raw)&.to_i
    end

    def decimal(raw)
      text = value(raw)
      return if text.blank?

      BigDecimal(text.tr(",", "."))
    rescue ArgumentError
      nil
    end

    def money_cents(raw)
      text = value(raw)
      return if text.blank?

      normalized = if text.include?(",")
                     text.tr(".", "").tr(",", ".")
                   else
                     text
                   end
      amount = BigDecimal(normalized)
      (amount * 100).round.to_i if amount
    rescue ArgumentError
      nil
    end

    def rent_total_cents(row)
      rent_cents = money_cents(row["VALOR_ALUGUEL"]) || money_cents(row["VLR_ALUGUEL"])
      return 0 unless rent_cents.to_i.positive?

      money_cents(row["VLR_TOTAL_ALUGUEL"]) || rent_cents
    end

    def date(raw)
      text = value(raw)
      return if text.blank? || text == "0000-00-00"

      Date.parse(text)
    rescue ArgumentError
      nil
    end

    def datetime(raw)
      text = value(raw)
      return if text.blank? || text == "0000-00-00" || text == "0000-00-00 00:00:00"

      Time.zone.parse(text)
    rescue ArgumentError
      nil
    end

    def track_error(scope, key, error)
      @stats[:"#{scope}_errors"] += 1
      @errors << { scope: scope, key: key, error: error.message }
      Rails.logger.warn("[Vista::CleanImportService] #{scope} #{key}: #{error.message}")
    end
  end
end

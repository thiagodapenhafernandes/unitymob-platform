module Vista
  class OperationalImportService
    BATCH_SIZE = 2_000

    Result = Struct.new(:batch_id, :dry_run, :tables, :total_rows, keyword_init: true)

    def initialize(batch: VistaImportBatch.latest_first.first, dry_run: true, reset: false, tables: nil)
      @batch = batch
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @reset = ActiveModel::Type::Boolean.new.cast(reset)
      @tables = Array(tables).flat_map { |value| value.to_s.split(",") }.map { |value| value.strip.upcase }.reject(&:blank?)
    end

    def call
      raise ArgumentError, "Nenhum batch Vista raw encontrado" unless @batch

      reset_tables! if @reset && !@dry_run
      load_reference_ids

      result = Result.new(batch_id: @batch.id, dry_run: @dry_run, tables: {}, total_rows: 0)
      importers.each do |table, importer|
        next if @tables.any? && !@tables.include?(table)

        count = import_table(table, importer)
        result.tables[table] = count
        result.total_rows += count
      end
      result
    end

    private

    def tenant
      Current.tenant || raise(ArgumentError, "Tenant obrigatório para importação operacional Vista")
    end

    def importers
      {
        "CDCLHI" => method(:client_interaction_attrs),
        "CDIMPRON" => method(:habitation_interaction_attrs),
        "AGENDA" => method(:appointment_attrs),
        "CDCLIAG" => method(:client_agent_link_attrs),
        "CSDSIM3" => method(:interest_attrs),
        "CSDSIM2" => method(:interest_profile_attrs)
      }
    end

    def reset_tables!
      tenant_habitation_ids = tenant.habitations.select(:id)
      tenant_proprietor_ids = tenant.proprietors.select(:id)
      tenant_admin_user_ids = tenant.admin_users.select(:id)

      [ClientInteraction, HabitationInteraction, CrmAppointment, ClientPropertyInterest].each do |model|
        model
          .where(habitation_id: tenant_habitation_ids)
          .or(model.where(proprietor_id: tenant_proprietor_ids))
          .or(model.where(admin_user_id: tenant_admin_user_ids))
          .delete_all
      end
    end

    def load_reference_ids
      @habitation_id_by_code = tenant.habitations.where.not(codigo: [nil, ""]).pluck(:codigo, :id).to_h
      @crm_contact_id_by_code = CrmContact.where.not(vista_code: [nil, ""]).pluck(:vista_code, :id).to_h
      @proprietor_id_by_code = tenant.proprietors.where.not(vista_code: [nil, ""]).pluck(:vista_code, :id).to_h
      @admin_user_id_by_code = tenant.admin_users.where.not(vista_id: [nil, ""]).pluck(:vista_id, :id).to_h
    end

    def import_table(table, importer)
      rows = []
      count = 0

      raw_scope(table).find_each(batch_size: BATCH_SIZE) do |record|
        count += 1
        next if @dry_run

        rows << importer.call(record).merge(created_at: Time.current, updated_at: Time.current)
        flush_rows(table, rows) if rows.size >= BATCH_SIZE
      end

      flush_rows(table, rows) unless @dry_run
      count
    end

    def raw_scope(table)
      @batch.vista_raw_records.where(table_name: table).order(:id)
    end

    def flush_rows(table, rows)
      return if rows.empty?

      model_for(table).upsert_all(rows, unique_by: unique_index_for(table))
      rows.clear
    end

    def model_for(table)
      case table
      when "CDCLHI"
        ClientInteraction
      when "CDIMPRON"
        HabitationInteraction
      when "AGENDA"
        CrmAppointment
      when "CDCLIAG", "CSDSIM2", "CSDSIM3"
        ClientPropertyInterest
      end
    end

    def unique_index_for(table)
      case table
      when "CDCLHI"
        "index_client_interactions_on_source_table_and_source_key"
      when "CDIMPRON"
        "index_habitation_interactions_on_source_table_and_source_key"
      when "AGENDA"
        "index_crm_appointments_on_source_table_and_source_key"
      else
        "index_client_property_interests_on_source_table_and_source_key"
      end
    end

    def client_interaction_attrs(record)
      payload = record.payload
      client_code = code(payload["CODIGO_C"])
      habitation_code = code(payload["CODIGO_O"])
      agent_code = code(payload["CODIGO_D"])

      {
        vista_import_batch_id: @batch.id,
        source_table: record.table_name,
        source_key: source_key(record, "CODIGO"),
        crm_contact_id: @crm_contact_id_by_code[client_code],
        proprietor_id: @proprietor_id_by_code[client_code],
        habitation_id: @habitation_id_by_code[habitation_code],
        admin_user_id: @admin_user_id_by_code[agent_code],
        vista_client_code: client_code,
        vista_habitation_code: habitation_code,
        vista_agent_code: agent_code,
        subject: value(payload["ASSUNTO"]) || value(payload["ASSUNTO_ALT"]),
        body: value(payload["TEXTO"]),
        interaction_type: value(payload["TIPO_ATIVIDADE_ID"]),
        activity_type_id: value(payload["TIPO_ATIVIDADE_ID"]),
        occurred_at: datetime_from_date_time(payload["DATA"], payload["HORA"]),
        return_at: datetime(payload["DATA_RETORNO"]),
        pending: yes?(payload["PENDENTE"]),
        automatic: yes?(payload["AUTOMATICO"]),
        lead: yes?(payload["LEAD"]),
        launch: yes?(payload["LANCAMENTO"]),
        acceptance: value(payload["ACEITACAO"]),
        visit_status: value(payload["STATUS_VISITA"]),
        lost_reason: value(payload["MOTIVO_LOST"]),
        capture_vehicle: value(payload["VEICULO_CAPTACAO"]),
        proposal_value_cents: money_cents(payload["VALOR_PROPOSTA"]),
        business_id: value(payload["NEGOCIO_ID"]),
        metadata: payload
      }
    end

    def habitation_interaction_attrs(record)
      payload = record.payload
      habitation_code = code(payload["CODIGO_O"])
      client_code = code(payload["CODIGO_C"])
      agent_code = code(payload["CODIGO_D"])

      {
        vista_import_batch_id: @batch.id,
        source_table: record.table_name,
        source_key: source_key(record, "CODIGO"),
        habitation_id: @habitation_id_by_code[habitation_code],
        crm_contact_id: @crm_contact_id_by_code[client_code],
        proprietor_id: @proprietor_id_by_code[client_code],
        admin_user_id: @admin_user_id_by_code[agent_code],
        vista_habitation_code: habitation_code,
        vista_client_code: client_code,
        vista_agent_code: agent_code,
        subject: value(payload["ASSUNTO"]),
        body: value(payload["TEXTO"]),
        interaction_type: value(payload["RETRANCA"]) || value(payload["TIPO_ATIVIDADE_ID"]),
        activity_type_id: value(payload["TIPO_ATIVIDADE_ID"]),
        occurred_at: datetime_from_date_time(payload["DATA"], payload["HORA"]),
        started_at: datetime(payload["DATA_INICIO"]),
        pending: yes?(payload["PENDENTE"]),
        automatic: yes?(payload["AUTOMATICO"]),
        private: yes?(payload["PRIVADO"]),
        proposal: yes?(payload["PROPOSTA"]),
        status: value(payload["STATUS_IMOVEL"]),
        advertised: value(payload["ANUNCIADO"]),
        published_vehicle: value(payload["VEICULO_PUBLICADO"]),
        key_requester: value(payload["SOLICITANTE_CHAVE"]),
        proposal_value_cents: money_cents(payload["VALOR_PROPOSTA"]),
        business_id: value(payload["NEGOCIO_ID"]),
        metadata: payload
      }
    end

    def appointment_attrs(record)
      payload = record.payload
      client_code = code(payload["CODIGO_C"])
      habitation_code = code(payload["CODIGO_O"])
      agent_code = code(payload["CODIGO_D"])

      {
        vista_import_batch_id: @batch.id,
        source_table: record.table_name,
        source_key: source_key(record, "NUMERO"),
        crm_contact_id: @crm_contact_id_by_code[client_code],
        proprietor_id: @proprietor_id_by_code[client_code],
        habitation_id: @habitation_id_by_code[habitation_code],
        admin_user_id: @admin_user_id_by_code[agent_code],
        vista_client_code: client_code,
        vista_habitation_code: habitation_code,
        vista_agent_code: agent_code,
        title: value(payload["ASSUNTO"]),
        description: value(payload["TEXTO"]),
        appointment_type: value(payload["TIPO"]),
        priority: value(payload["PRIORIDADE"]),
        location: value(payload["LOCAL"]),
        starts_at: datetime(payload["INICIO"]),
        ends_at: datetime(payload["FINAL"]),
        completed_at: datetime(payload["DATA_CONCLUSAO"]),
        created_in_source_at: datetime(payload["DATA_HORA"]),
        task: yes?(payload["TAREFA"]),
        completed: yes?(payload["CONCLUIDO"]),
        all_day: yes?(payload["DIA_INTEIRO"]),
        private: yes?(payload["PRIVADO"]),
        deleted: yes?(payload["EXCLUIDO"]),
        reminder_minutes: integer(payload["ALERTA_MINUTOS"]),
        sms_client: yes?(payload["SMS_CLIENTE"]),
        sms_owner: yes?(payload["SMS_PROPRIETARIO"]),
        synced_with_source: yes?(payload["SINCRONIZADO"]),
        source_updated_at: datetime(payload["DH_ATUALIZACAO"]),
        visit_status: value(payload["STATUS_VISITA"]),
        google_calendar_id: value(payload["ID_GOOGLE_CALENDAR"]),
        business_id: value(payload["NEGOCIO_ID"]),
        metadata: payload
      }
    end

    def client_agent_link_attrs(record)
      payload = record.payload
      client_code = code(payload["CODIGO_C"])
      agent_code = code(payload["CODIGO_D"])

      {
        vista_import_batch_id: @batch.id,
        source_table: record.table_name,
        source_key: source_key(record, "NUMERO"),
        crm_contact_id: @crm_contact_id_by_code[client_code],
        proprietor_id: @proprietor_id_by_code[client_code],
        admin_user_id: @admin_user_id_by_code[agent_code],
        vista_client_code: client_code,
        vista_agent_code: agent_code,
        interest_type: "client_agent_link",
        started_at: datetime(payload["DATA_INI"]),
        metadata: payload
      }
    end

    def interest_attrs(record)
      payload = record.payload
      client_code = code(payload["CODIGO_C"])
      habitation_code = code(payload["CODIGO_O"])

      {
        vista_import_batch_id: @batch.id,
        source_table: record.table_name,
        source_key: source_key(record, "CODIGO"),
        crm_contact_id: @crm_contact_id_by_code[client_code],
        proprietor_id: @proprietor_id_by_code[client_code],
        habitation_id: @habitation_id_by_code[habitation_code],
        vista_client_code: client_code,
        vista_habitation_code: habitation_code,
        interest_type: value(payload["TIPO_CS"]) || "property_interest",
        notes: value(payload["OBS"]),
        selected: yes?(payload["SELECIONADO"]),
        awaited: yes?(payload["AGUARDADO"]),
        lead: yes?(payload["LEAD"]),
        business_id: value(payload["NEGOCIO_ID"]),
        metadata: payload
      }
    end

    def interest_profile_attrs(record)
      payload = record.payload
      client_code = code(payload["CODIGO_C"])
      habitation_code = code(payload["CODIGO_IMO"])
      agent_code = code(payload["CODIGO_M"])

      {
        vista_import_batch_id: @batch.id,
        source_table: record.table_name,
        source_key: source_key(record, "CODIGO"),
        crm_contact_id: @crm_contact_id_by_code[client_code],
        proprietor_id: @proprietor_id_by_code[client_code],
        habitation_id: @habitation_id_by_code[habitation_code],
        admin_user_id: @admin_user_id_by_code[agent_code],
        vista_client_code: client_code,
        vista_habitation_code: habitation_code,
        vista_agent_code: agent_code,
        interest_type: value(payload["TIPO_CS"]) || "profile_search",
        status: value(payload["STATUS"]),
        notes: value(payload["OBS"]),
        awaited: yes?(payload["AGUARDANDO"]),
        started_at: datetime(payload["DATA_INI"]),
        ended_at: datetime(payload["DATA_FIN"]),
        consulted_at: datetime(payload["DATA_CONSULTA"]),
        last_search_at: datetime(payload["DH_ULTIMA_BUSCA"]),
        business_id: value(payload["NEGOCIO_ID"]),
        criteria: payload.except("CODIGO", "CODIGO_C", "CODIGO_IMO", "CODIGO_M", "OBS", "STATUS", "NEGOCIO_ID"),
        metadata: payload
      }
    end

    def source_key(record, field)
      base = value(record.payload[field]) || record.source_key || record.row_index.to_s
      "#{base}:raw#{record.id}"
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

    def datetime(raw)
      text = value(raw)
      return if text.blank? || text == "0000-00-00" || text == "0000-00-00 00:00:00"

      Time.zone.parse(text)
    rescue ArgumentError, TypeError
      nil
    end

    def datetime_from_date_time(date, time)
      date_text = value(date)
      return datetime(date_text) if value(time).blank?

      datetime("#{date_text} #{value(time)}")
    end

    def money_cents(raw)
      text = value(raw)
      return if text.blank?

      normalized = text.tr(".", "").tr(",", ".")
      (BigDecimal(normalized) * 100).round.to_i
    rescue ArgumentError
      nil
    end

    def integer(raw)
      value(raw)&.to_i
    end
  end
end

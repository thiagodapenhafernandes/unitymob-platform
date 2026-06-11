require "set"

module Vista
  class FileAssetIndexService
    PHOTO_BASE_URL = "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/fotos/".freeze
    DOCUMENT_BASE_URL = "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/documentos/".freeze
    AGENT_BASE_URL = "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/usuarios/".freeze
    CLIENT_BASE_URL = "https://cdn.vistahost.com.br/saluteim20174/vista.imobi/clientes/".freeze
    BATCH_SIZE = 1_000

    Result = Struct.new(:batch_id, :dry_run, :scanned, :indexed, :skipped, :by_kind, keyword_init: true)

    def initialize(batch: VistaImportBatch.latest_first.first, dry_run: true, reset: false)
      @batch = batch
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @reset = ActiveModel::Type::Boolean.new.cast(reset)
      @seen_sources = Set.new
    end

    def call
      raise ArgumentError, "Nenhum batch Vista raw encontrado" unless @batch

      VistaFileAsset.where(vista_import_batch: @batch).delete_all if @reset && !@dry_run

      result = Result.new(batch_id: @batch.id, dry_run: @dry_run, scanned: 0, indexed: 0, skipped: 0, by_kind: Hash.new(0))
      rows = []
      habitation_id_by_code = Habitation.where.not(codigo: [nil, ""]).pluck(:codigo, :id).to_h

      raw_scope.find_each(batch_size: BATCH_SIZE) do |record|
        result.scanned += 1
        attrs = asset_attributes(record, habitation_id_by_code)

        if attrs.blank?
          result.skipped += 1
          next
        end

        source_key = [@batch.id, attrs[:table_name], attrs[:source_path]]
        if @seen_sources.include?(source_key)
          result.skipped += 1
          next
        end
        @seen_sources << source_key

        result.by_kind[attrs[:kind]] += 1
        result.indexed += 1
        next if @dry_run

        rows << attrs.merge(
          vista_import_batch_id: @batch.id,
          vista_raw_record_id: record.id,
          created_at: Time.current,
          updated_at: Time.current
        )
        flush_rows(rows) if rows.size >= BATCH_SIZE
      end

      flush_rows(rows) unless @dry_run
      result
    end

    private

    def raw_scope
      @batch.vista_raw_records.where(table_name: %w[CDIMIM CDIMDC CDCLDC CDEMDC CMPN1 CADIMO])
    end

    def flush_rows(rows)
      return if rows.empty?

      VistaFileAsset.upsert_all(
        rows,
        unique_by: "idx_vista_file_assets_unique_source"
      )
      rows.clear
    end

    def asset_attributes(record, habitation_id_by_code)
      path = source_path(record)
      return if path.blank?

      kind = kind_for(record.table_name)
      source_url = source_url_for(kind, path)
      filename = File.basename(URI.parse(source_url).path)
      return if filename.blank?

      {
        table_name: record.table_name,
        kind: kind,
        status: "pending",
        codigo_imovel: record.codigo_imovel,
        codigo_cliente: record.codigo_cliente,
        codigo_corretor: record.codigo_corretor,
        habitation_id: record.codigo_imovel.present? ? habitation_id_by_code[record.codigo_imovel] : nil,
        source_path: path,
        source_url: source_url,
        filename: filename,
        active_storage_name: active_storage_name_for(kind),
        position: integer_value(record.payload["ORDEM"]),
        metadata: record.payload
      }
    rescue URI::InvalidURIError
      nil
    end

    def source_path(record)
      payload = record.payload
      value = payload["FILE_PATH"] || payload["ARQUIVO"] || payload["FILE_PATH_O"] || payload["FILE_PATH_P"]
      present_value(value)
    end

    def kind_for(table_name)
      case table_name
      when "CDIMIM", "CADIMO"
        "property_photo"
      when "CDIMDC"
        "property_document"
      when "CDCLDC"
        "client_document"
      when "CDEMDC", "CMPN1"
        "agent_document"
      else
        "other"
      end
    end

    def active_storage_name_for(kind)
      case kind
      when "property_photo"
        "photos"
      when "property_document"
        "autorizacoes_venda"
      end
    end

    def source_url_for(kind, path)
      return path if path.match?(%r{\Ahttps?://}i)

      base_url = case kind
                 when "property_photo" then PHOTO_BASE_URL
                 when "property_document" then DOCUMENT_BASE_URL
                 when "client_document" then CLIENT_BASE_URL
                 when "agent_document" then AGENT_BASE_URL
                 else PHOTO_BASE_URL
                 end

      URI.join(base_url, path).to_s
    end

    def present_value(value)
      return if value.nil?

      value = value.to_s.strip
      value.presence unless value == "NULL" || value == "\\N"
    end

    def integer_value(value)
      present_value(value)&.to_i
    end
  end
end

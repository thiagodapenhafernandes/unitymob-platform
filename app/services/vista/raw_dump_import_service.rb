module Vista
  class RawDumpImportService
    DEFAULT_DUMP_DIR = DumpImportService::DEFAULT_DUMP_DIR
    DEFAULT_BATCH_SIZE = 1_000

    HABITATION_CODE_FIELDS = {
      "AGENDA" => "CODIGO_O",
      "AUTIMO" => "CODIGO",
      "AUTIMODC" => "CODIGO_O",
      "CADIMO" => "CODIGO",
      "CDCLHI" => "CODIGO_O",
      "CDIMAG" => "CODIGO_O",
      "CDIMCHAV" => "CODIGO_O",
      "CDIMCMPR" => "CODIGO_O",
      "CDIMDC" => "CODIGO_O",
      "CDIMIM" => "CODIGO",
      "CDIMPRON" => "CODIGO_O",
      "CDIMVD" => "CODIGO",
      "CHAVEIRO_IMOVEL" => "CODIGO_O",
      "CSDSIM2" => "CODIGO_IMO",
      "CSDSIM3" => "CODIGO_O",
      "DIMOB" => "CODIGO_O",
      "DIMOB_CS" => "CODIGO_O"
    }.freeze

    CLIENT_CODE_FIELDS = {
      "AGENDA" => "CODIGO_C",
      "CADCLI" => "CODIGO_C",
      "CDCLCMHI" => "CODIGO_C",
      "CDCLCMUT" => "CODIGO_C",
      "CDCLDC" => "CODIGO_C",
      "CDCLHI" => "CODIGO_C",
      "CDCLIAG" => "CODIGO_C",
      "CDCSCMUT" => "CODIGO_C",
      "CSDSIM2" => "CODIGO_C",
      "CSDSIM3" => "CODIGO_C",
      "DIMOB_C" => "CODIGO_C",
      "DIMOB_P" => "CODIGO_C"
    }.freeze

    BROKER_CODE_FIELDS = {
      "AGENDA" => "CODIGO_D",
      "CADEMP" => "CODIGO_D",
      "CDEMCMUT" => "CODIGO_D",
      "CDEMCTPR" => "CODIGO_D",
      "CDEMDC" => "CODIGO_D",
      "CDIMAG" => "CODIGO_D",
      "CDIMDC" => "CODIGO_D",
      "CDIMPRON" => "CODIGO_D"
    }.freeze

    SOURCE_KEY_FIELDS = {
      "AGENDA" => %w[NUMERO],
      "CADCLI" => %w[CODIGO_C],
      "CADEMP" => %w[CODIGO_D],
      "CADIMO" => %w[CODIGO],
      "CDCLHI" => %w[CODIGO],
      "CDIMAG" => %w[NUMERO CODIGO_O CODIGO_D],
      "CDIMDC" => %w[CODIGO_O CODIGO_DOC],
      "CDIMIM" => %w[CODIGO CODIGO_I],
      "CDIMPRON" => %w[CODIGO],
      "CDIMVD" => %w[CODIGO CODIGO_I]
    }.freeze

    FALLBACK_SOURCE_KEY_FIELDS = %w[CODIGO CODIGO_C CODIGO_D NUMERO ID].freeze

    Result = Struct.new(
      :dry_run,
      :dump_dir,
      :batch,
      :tables,
      :total_rows,
      :errors,
      keyword_init: true
    )

    def initialize(dump_dir: DEFAULT_DUMP_DIR, dry_run: true, tables: nil, batch_size: DEFAULT_BATCH_SIZE, truncate: false)
      dump_path = Pathname.new(dump_dir.to_s)
      @dump_dir = dump_path.absolute? ? dump_path : Rails.root.join(dump_path)
      @dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
      @tables = Array(tables).flat_map { |value| value.to_s.split(",") }.map { |value| value.strip.upcase }.reject(&:blank?)
      @batch_size = batch_size.to_i.positive? ? batch_size.to_i : DEFAULT_BATCH_SIZE
      @truncate = ActiveModel::Type::Boolean.new.cast(truncate)
    end

    def call
      validate_dump!

      result = Result.new(
        dry_run: @dry_run,
        dump_dir: @dump_dir.to_s,
        batch: nil,
        tables: {},
        total_rows: 0,
        errors: []
      )

      batch = nil

      unless @dry_run
        VistaRawRecord.delete_all if @truncate
        VistaImportBatch.delete_all if @truncate
        batch = VistaImportBatch.create!(dump_dir: @dump_dir.to_s, status: "running", started_at: Time.current)
        result.batch = batch
      end

      each_sql_table do |table, path|
        table_result = import_table(table, path, batch)
        result.tables[table] = table_result
        result.total_rows += table_result[:rows]
      rescue StandardError => e
        result.errors << { table: table, error: e.message }
      end

      if batch
        batch.update!(
          status: result.errors.any? ? "failed" : "completed",
          finished_at: Time.current,
          metadata: { "tables" => result.tables, "total_rows" => result.total_rows },
          error_message: result.errors.map { |error| "#{error[:table]}: #{error[:error]}" }.join("\n").presence
        )
      end

      result
    rescue StandardError => e
      batch&.update(status: "failed", finished_at: Time.current, error_message: e.message)
      raise
    end

    private

    def validate_dump!
      raise ArgumentError, "Diretorio nao encontrado: #{@dump_dir}" unless @dump_dir.directory?
      raise ArgumentError, "Nenhum arquivo .sql encontrado em #{@dump_dir}" if sql_paths.empty?
    end

    def sql_paths
      @sql_paths ||= @dump_dir.children.select { |path| path.file? && path.extname.casecmp(".sql").zero? }.sort_by { |path| path.basename.to_s }
    end

    def each_sql_table
      sql_paths.each do |path|
        table = path.basename(".sql").to_s.upcase
        next if @tables.any? && !@tables.include?(table)

        yield table, path
      end
    end

    def import_table(table, path, batch)
      now = Time.current
      rows = []
      row_count = 0
      columns = []

      each_row(path, table) do |row|
        row_count += 1
        columns = row.keys if columns.empty?

        next if @dry_run

        rows << raw_record_attributes(batch, table, row_count, row, now)
        flush_rows(rows) if rows.size >= @batch_size
      end

      flush_rows(rows) unless @dry_run

      {
        rows: row_count,
        columns: columns.size,
        file: path.to_s,
        bytes: path.size
      }
    end

    def raw_record_attributes(batch, table, row_index, row, timestamp)
      {
        vista_import_batch_id: batch.id,
        table_name: table,
        row_index: row_index,
        source_key: source_key(table, row),
        codigo_imovel: linked_code(row, HABITATION_CODE_FIELDS[table]),
        codigo_cliente: linked_code(row, CLIENT_CODE_FIELDS[table]),
        codigo_corretor: linked_code(row, BROKER_CODE_FIELDS[table]),
        payload: row,
        created_at: timestamp,
        updated_at: timestamp
      }
    end

    def flush_rows(rows)
      return if rows.empty?

      VistaRawRecord.insert_all!(rows)
      rows.clear
    end

    def source_key(table, row)
      fields = SOURCE_KEY_FIELDS.fetch(table, FALLBACK_SOURCE_KEY_FIELDS)
      values = fields.filter_map { |field| linked_code(row, field) }
      values.presence&.join(":")
    end

    def linked_code(row, field)
      return if field.blank?

      value = row[field]
      return if blankish?(value)

      value.to_s.strip
    end

    def blankish?(value)
      value.nil? || value == "" || value == "NULL" || value == "\\N"
    end

    def normalize_encoding(value)
      value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end

    def each_row(path, table)
      content = File.binread(path)
      needle = "INSERT INTO `#{table}`"
      pos = 0

      while (start = content.index(needle, pos))
        values_pos = content.index("VALUES", start)
        raise "VALUES nao encontrado em #{path} apos byte #{start}" unless values_pos

        columns = columns_from_header(content[start...values_pos], table)
        pos = each_insert_row(content, values_pos + "VALUES".bytesize, columns) do |row|
          yield row
        end
      end
    end

    def columns_from_header(header, table)
      columns = header.scan(/`([^`]+)`/).flatten.map { |column| normalize_encoding(column) }
      columns.shift if columns.first == table
      columns
    end

    def each_insert_row(content, offset, columns)
      i = offset
      quote = nil
      escape = false
      fields = nil
      current = +""
      depth = 0

      while i < content.bytesize
        byte = content.getbyte(i)

        if quote
          if escape
            current << byte
            escape = false
          elsif byte == 92
            escape = true
          elsif byte == quote
            quote = nil
          else
            current << byte
          end
        else
          case byte
          when 34, 39
            quote = byte
          when 40
            if depth.zero?
              fields = []
              current = +""
            else
              current << byte
            end
            depth += 1
          when 44
            if depth == 1
              fields << normalize_encoding(current)
              current = +""
            elsif depth.positive?
              current << byte
            end
          when 41
            if depth == 1
              fields << normalize_encoding(current)
              yield columns.zip(fields).to_h
              fields = nil
              current = +""
              depth = 0
            elsif depth.positive?
              current << byte
              depth -= 1
            end
          when 59
            return i + 1 if depth.zero?

            current << byte
          else
            current << byte if depth.positive?
          end
        end

        i += 1
      end

      i
    end
  end
end

namespace :data do
  desc "Autofill constructor_id for developments without constructor (safe mode + CSV report). Use APPLY=true to persist."
  task backfill_development_constructors: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch("APPLY", "false"))
    result = Habitations::DevelopmentConstructorBackfillService.new(apply: apply).call

    puts "Backfill de construtoras em empreendimentos"
    puts "  missing_total: #{result.missing_total}"
    puts "  auto_filled: #{result.auto_filled}"
    puts "  suggested: #{result.suggested}"
    puts "  unresolved: #{result.unresolved}"
    puts "  report: #{result.report_path}"
    puts "  mode: #{apply ? 'APPLY' : 'DRY-RUN'}"
  end

  desc "Audit hierarchy consistency (unit -> development -> constructor). Use STRICT=true to fail on critical issues."
  task audit_hierarchy: :environment do
    strict = ActiveModel::Type::Boolean.new.cast(ENV.fetch("STRICT", "false"))
    result = Habitations::HierarchyAuditService.new(strict: strict).call
    puts JSON.pretty_generate(result)
  rescue StandardError => e
    warn e.message
    exit 1
  end

  desc "Reconcile units with invalid parent links. Use APPLY=true to persist."
  task reconcile_invalid_parents: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch("APPLY", "false"))
    result = Habitations::InvalidParentReconciliationService.new(apply: apply).call

    puts "Reconciliação de vínculos inválidos (unidade -> empreendimento)"
    puts "  invalid_total: #{result.invalid_total}"
    puts "  reconciled: #{result.reconciled}"
    puts "  promoted_parents: #{result.promoted_parents}"
    puts "  unresolved: #{result.unresolved}"
    puts "  report: #{result.report_path}"
    puts "  mode: #{apply ? 'APPLY' : 'DRY-RUN'}"
  end

  desc "Backfill missing development parents from Vista and then reconcile invalid parent links. Use APPLY=true to persist. Optional LIMIT=100."
  task reconcile_invalid_parents_from_vista: :environment do
    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch("APPLY", "false"))
    limit = ENV["LIMIT"].presence

    result = Habitations::InvalidParentVistaBackfillService.new(apply: apply, limit: limit).call
    reconciliation = result.reconciliation_result

    puts "Reconciliação via Vista (pais faltantes)"
    puts "  invalid_parent_codes_total: #{result.invalid_parent_codes_total}"
    puts "  processed_codes: #{result.processed_codes}"
    puts "  fetched_from_vista: #{result.fetched_from_vista}"
    puts "  created_or_updated_developments: #{result.created_or_updated_developments}"
    puts "  vista_not_found: #{result.not_found_in_vista.size}"
    puts "  errors: #{result.errors.size}"
    puts "  mode: #{apply ? 'APPLY' : 'DRY-RUN'}"
    puts "  limit: #{limit || 'none'}"
    puts "  --- reconciliation ---"
    puts "  invalid_total: #{reconciliation.invalid_total}"
    puts "  reconciled: #{reconciliation.reconciled}"
    puts "  unresolved: #{reconciliation.unresolved}"
    puts "  report: #{reconciliation.report_path}"
  end

  desc "Export unresolved invalid parent links to CSV (detailed + grouped)"
  task export_unresolved_invalid_parents: :environment do
    require "csv"
    require "fileutils"
    require "set"

    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    reports_dir = Rails.root.join("tmp", "reports")
    FileUtils.mkdir_p(reports_dir)

    valid_dev_codes = Habitation.empreendimentos.where.not(codigo: [nil, ""]).pluck(:codigo).map(&:to_s).to_set

    unresolved_scope = Habitation.where.not(codigo_empreendimento: [nil, ""])
                                .where.not(codigo_empreendimento: valid_dev_codes.to_a)

    detailed_path = reports_dir.join("unresolved_invalid_parents_detailed_#{timestamp}.csv")
    grouped_path = reports_dir.join("unresolved_invalid_parents_grouped_#{timestamp}.csv")

    detail_rows = unresolved_scope
      .left_outer_joins(:address)
      .select(
        "habitations.id",
        "habitations.codigo",
        "habitations.codigo_empreendimento",
        "habitations.nome_empreendimento",
        "habitations.categoria",
        "habitations.status",
        "habitations.situacao",
        "COALESCE(addresses.cidade, habitations.cidade) AS cidade_nome",
        "COALESCE(addresses.bairro, habitations.bairro) AS bairro_nome",
        "habitations.updated_at"
      )
      .order("habitations.codigo_empreendimento ASC, habitations.codigo ASC")

    CSV.open(detailed_path, "w") do |csv|
      csv << %w[
        unit_id
        unit_code
        current_parent_code
        unit_development_name
        category
        status
        situation
        city
        neighborhood
        updated_at
      ]

      detail_rows.each do |row|
        csv << [
          row.id,
          row.codigo,
          row.codigo_empreendimento,
          row.nome_empreendimento,
          row.categoria,
          row.status,
          row.situacao,
          row.read_attribute("cidade_nome"),
          row.read_attribute("bairro_nome"),
          row.updated_at
        ]
      end
    end

    grouped_rows = unresolved_scope
      .group(:codigo_empreendimento)
      .order(Arel.sql("COUNT(*) DESC"), :codigo_empreendimento)
      .count

    CSV.open(grouped_path, "w") do |csv|
      csv << %w[parent_code units_count sample_unit_code sample_development_name]

      grouped_rows.each do |parent_code, count|
        sample = unresolved_scope
          .where(codigo_empreendimento: parent_code)
          .order(:codigo)
          .limit(1)
          .pluck(:codigo, :nome_empreendimento)
          .first

        csv << [parent_code, count, sample&.first, sample&.last]
      end
    end

    puts "CSV detalhado: #{detailed_path}"
    puts "CSV agrupado: #{grouped_path}"
    puts "Total unidades sem pai válido: #{unresolved_scope.count}"
    puts "Total códigos de pai inválido: #{grouped_rows.size}"
  end

  desc "Export unresolved developments (without constructor) to CSV for manual mapping"
  task export_missing_development_constructors: :environment do
    require "csv"
    require "fileutils"

    rows = Habitation.empreendimentos
                     .where(constructor_id: nil)
                     .order(:nome_empreendimento, :codigo)
                     .pluck(:id, :codigo, :nome_empreendimento, :cidade, :bairro)

    path = Rails.root.join("tmp", "reports", "missing_development_constructors_manual.csv")
    FileUtils.mkdir_p(path.dirname)

    CSV.open(path, "w") do |csv|
      csv << %w[development_id codigo nome_empreendimento cidade bairro constructor_id constructor_name]
      rows.each do |id, codigo, nome, cidade, bairro|
        csv << [id, codigo, nome, cidade, bairro, nil, nil]
      end
    end

    puts "Arquivo gerado: #{path}"
    puts "Pendentes: #{rows.size}"
  end

  desc "Apply manual CSV mapping of development -> constructor_id (FILE=tmp/reports/missing_development_constructors_manual.csv)"
  task apply_development_constructor_mapping: :environment do
    require "csv"

    file = ENV["FILE"].presence || Rails.root.join("tmp", "reports", "missing_development_constructors_manual.csv").to_s
    abort("Arquivo não encontrado: #{file}") unless File.exist?(file)

    applied = 0
    skipped = 0

    CSV.foreach(file, headers: true) do |row|
      development_id = row["development_id"].to_i
      constructor_id = row["constructor_id"].to_i

      if development_id.zero? || constructor_id.zero?
        skipped += 1
        next
      end

      development = Habitation.empreendimentos.find_by(id: development_id)
      constructor = Constructor.find_by(id: constructor_id)

      if development.nil? || constructor.nil?
        skipped += 1
        next
      end

      development.update_columns(
        constructor_id: constructor.id,
        construtora: constructor.name,
        updated_at: Time.current
      )

      Habitation.where(codigo_empreendimento: development.codigo).update_all(
        constructor_id: constructor.id,
        construtora: constructor.name,
        updated_at: Time.current
      )

      applied += 1
    end

    puts "Mapeamento manual aplicado."
    puts "  applied: #{applied}"
    puts "  skipped: #{skipped}"
  end

  desc "Export manual CSV prefilled with constructor suggestions (no DB changes)."
  task prefill_missing_development_constructors: :environment do
    require "csv"
    require "fileutils"

    min_confidence = ENV.fetch("MIN_CONFIDENCE", "0.60")
    min_margin = ENV.fetch("MIN_MARGIN", "0.05")

    result = Habitations::DevelopmentConstructorBackfillService.new(
      apply: false,
      min_confidence: min_confidence,
      min_margin: min_margin
    ).call

    path = Rails.root.join("tmp", "reports", "missing_development_constructors_manual_prefilled.csv")
    FileUtils.mkdir_p(path.dirname)

    CSV.open(path, "w") do |csv|
      csv << %w[
        development_id
        codigo
        nome_empreendimento
        constructor_id
        constructor_name
        confidence
        reason
      ]
      result.rows.sort_by { |row| [row[:development_name].to_s.downcase, row[:development_code].to_s] }.each do |row|
        csv << [
          row[:development_id],
          row[:development_code],
          row[:development_name],
          row[:suggested_constructor_id],
          row[:suggested_constructor_name],
          row[:confidence],
          row[:reason]
        ]
      end
    end

    puts "CSV prefilled gerado: #{path}"
    puts "  missing_total: #{result.missing_total}"
    puts "  suggested: #{result.suggested}"
    puts "  unresolved: #{result.unresolved}"
    puts "  thresholds: min_confidence=#{min_confidence}, min_margin=#{min_margin}"
  end
end

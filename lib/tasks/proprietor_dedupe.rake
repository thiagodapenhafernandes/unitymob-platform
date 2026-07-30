# Diagnóstico e fusão de proprietários duplicados (herança da base suja do Vista).
#
#   bin/rails proprietors:duplicate_report
#   bin/rails proprietors:duplicate_report TENANT_ID=1
#   bin/rails proprietors:merge_candidates               # DRY-RUN dos candidatos automaticos
#   bin/rails proprietors:merge_candidates EXECUTE=1     # executa candidatos automaticos
#   bin/rails proprietors:merge_candidates EXECUTE=1 RISKS=automatic_candidate,review_required
#   bin/rails proprietors:merge_ids CANONICAL_ID=3884 DUPLICATE_IDS=37139,37140
#   bin/rails proprietors:merge_ids CANONICAL_CODE=3884 DUPLICATE_CODES=37139,37140
#   bin/rails proprietors:merge_ids CANONICAL_ID=3884 DUPLICATE_IDS=37139,37140 EXECUTE=1
#   bin/rails proprietors:dedupe                    # DRY-RUN legado (só relata)
#   bin/rails proprietors:dedupe EXECUTE=1          # executa fusão por nome exato; usar só após revisar CSV
#
# Regras da fusão legada:
# - Grupo = mesmo nome normalizado (lower/trim) dentro da conta.
# - Canônico = o que tem mais imóveis vinculados; empate: o mais antigo (menor id).
# - Duplicados: imóveis reapontados ao canônico, dados que só eles têm são
#   copiados para o canônico (campos em branco), e então removidos.
# - Log reversível em log/proprietor_merge_<data>.csv (deleted_id → canonical_id).
# - O sync do Vista NÃO recria os removidos: o reconciliation reusa por nome
#   (ver Vista::PropertyReconciliationService#resolve_proprietor).
namespace :proprietors do
  def proprietor_tenant_scope
    ENV["TENANT_ID"].present? ? Tenant.where(id: ENV["TENANT_ID"]) : Tenant.all
  end

  def proprietor_merge_reference(prefix)
    id = ENV["#{prefix}_ID"].to_i
    code = ENV["#{prefix}_CODE"].to_s.strip
    scope = ENV["TENANT_ID"].present? ? Proprietor.where(tenant_id: ENV["TENANT_ID"]) : Proprietor.all

    return scope.find_by(id: id) if id.positive?
    return nil if code.blank?

    scope.where(vista_code: code).to_a.max_by { |proprietor| proprietor_merge_score(proprietor) }
  end

  def proprietor_merge_duplicates(canonical)
    ids = ENV.fetch("DUPLICATE_IDS", "").split(",").map { |id| id.to_s.strip.to_i }.reject(&:zero?)
    codes = ENV.fetch("DUPLICATE_CODES", "").split(",").map { |code| code.to_s.strip }.reject(&:blank?)
    scope = ENV["TENANT_ID"].present? ? Proprietor.where(tenant_id: ENV["TENANT_ID"]) : Proprietor.all

    duplicates = []
    duplicates += scope.where(id: ids).to_a if ids.any?
    duplicates += scope.where(vista_code: codes).to_a if codes.any?
    duplicates.uniq.reject { |proprietor| proprietor.id == canonical.id }.sort_by(&:id)
  end

  def proprietor_merge_score(proprietor)
    [
      proprietor_reference_count(proprietor),
      %i[name vista_code cpf_cnpj_digits email phone_primary mobile_phone residential_phone business_phone city street cep notes].count { |field| proprietor.respond_to?(field) && proprietor.public_send(field).present? },
      proprietor.created_at ? -proprietor.created_at.to_i : 0,
      -proprietor.id
    ]
  end

  def proprietor_reference_count(proprietor)
    Proprietors::DuplicateAnalyzer::REFERENCING_TABLES.sum do |table|
      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(["SELECT COUNT(*) FROM #{table} WHERE proprietor_id = ?", proprietor.id])
      ).to_i
    end
  end

  desc "Gera CSV com candidatos a proprietários duplicados, sem alterar dados"
  task duplicate_report: :environment do
    require "csv"

    tenant_scope = proprietor_tenant_scope
    analyzer = Proprietors::DuplicateAnalyzer.new(tenant_scope: tenant_scope)
    candidates = analyzer.call
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    report_path = Rails.root.join("tmp", "proprietor_duplicate_candidates_#{timestamp}.csv")

    CSV.open(report_path, "w") do |csv|
      csv << %w[
        tenant_id risk match_type match_key proprietor_count linked_records_count
        canonical_id canonical_name canonical_vista_code canonical_email canonical_phone canonical_mobile
        duplicate_ids duplicate_names duplicate_vista_codes duplicate_emails duplicate_phones reason
      ]

      candidates.each do |candidate|
        canonical = candidate.canonical_snapshot
        duplicates = candidate.duplicate_snapshots

        csv << [
          candidate.tenant_id,
          candidate.risk,
          candidate.match_type,
          candidate.match_key,
          candidate.proprietor_count,
          candidate.linked_records_count,
          candidate.canonical_id,
          canonical[:name],
          canonical[:vista_code],
          canonical[:email],
          canonical[:phone_primary],
          canonical[:mobile_phone],
          candidate.duplicate_ids.join("|"),
          duplicates.map { |item| item[:name] }.join("|"),
          duplicates.map { |item| item[:vista_code] }.join("|"),
          duplicates.map { |item| item[:email] }.join("|"),
          duplicates.map { |item| item[:phone_primary].presence || item[:mobile_phone] }.join("|"),
          candidate.reason
        ]
      end
    end

    summary = candidates.group_by(&:risk).transform_values(&:count)
    puts "Relatório gerado: #{report_path}"
    puts "Total de candidatos: #{candidates.size}"
    puts "automatic_candidate: #{summary.fetch('automatic_candidate', 0)}"
    puts "review_required: #{summary.fetch('review_required', 0)}"
    puts "high_risk: #{summary.fetch('high_risk', 0)}"
  end

  desc "Funde candidatos do relatório por risco permitido (DRY-RUN por padrão; EXECUTE=1 aplica)"
  task merge_candidates: :environment do
    require "csv"
    require "set"

    execute = ENV["EXECUTE"] == "1"
    risks = ENV.fetch("RISKS", "automatic_candidate").split(",").map(&:strip).reject(&:blank?)
    tenant_scope = proprietor_tenant_scope
    candidates = Proprietors::DuplicateAnalyzer.new(tenant_scope: tenant_scope).call
    merger = Proprietors::DuplicateMerger.new(candidates: candidates, risks: risks, execute: execute)
    result = merger.call

    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'} risks=#{risks.join(',')}"
    puts "#{result.groups} grupos | #{result.deleted} duplicados #{execute ? 'removidos' : 'a remover'} | #{result.repointed} referências #{execute ? 'reapontadas' : 'a reapontar'} | #{result.skipped} ignorados"
    puts "log: #{result.log_path}" if result.log_path
  end

  desc "Funde proprietários específicos por ID ou código Vista (DRY-RUN por padrão; EXECUTE=1 aplica)"
  task merge_ids: :environment do
    execute = ENV["EXECUTE"] == "1"

    abort "Informe CANONICAL_ID ou CANONICAL_CODE." if ENV["CANONICAL_ID"].blank? && ENV["CANONICAL_CODE"].blank?
    abort "Informe DUPLICATE_IDS ou DUPLICATE_CODES separados por vírgula." if ENV["DUPLICATE_IDS"].blank? && ENV["DUPLICATE_CODES"].blank?

    canonical = proprietor_merge_reference("CANONICAL")
    abort "Proprietário canônico não encontrado." unless canonical

    duplicates = proprietor_merge_duplicates(canonical)
    abort "Nenhum duplicado encontrado para os parâmetros informados." if duplicates.blank?

    different_tenant_ids = duplicates.map(&:tenant_id).uniq - [canonical.tenant_id]
    abort "Todos os proprietários precisam pertencer ao mesmo tenant do canônico." if different_tenant_ids.any?

    candidate = Proprietors::DuplicateAnalyzer::Candidate.new(
      tenant_id: canonical.tenant_id,
      match_type: "manual_ids",
      match_key: "canonical:#{canonical.id}",
      risk: "manual",
      reason: "Fusão manual informada por IDs",
      canonical_id: canonical.id,
      duplicate_ids: duplicates.map(&:id),
      proprietor_count: duplicates.size + 1,
      linked_records_count: nil,
      canonical_snapshot: { id: canonical.id, name: canonical.name, vista_code: canonical.vista_code },
      duplicate_snapshots: duplicates.map { |proprietor| { id: proprietor.id, name: proprietor.name, vista_code: proprietor.vista_code } }
    )

    result = Proprietors::DuplicateMerger.new(candidates: [candidate], risks: ["manual"], execute: execute).call

    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'} canonical=#{canonical.id} duplicate_ids=#{duplicates.map(&:id).join(',')}"
    puts "#{result.groups} grupo | #{result.deleted} duplicados #{execute ? 'removidos' : 'a remover'} | #{result.repointed} referências #{execute ? 'reapontadas' : 'a reapontar'} | #{result.skipped} ignorados"
    puts "log: #{result.log_path}" if result.log_path
  end

  desc "Funde proprietários duplicados por nome (DRY-RUN por padrão; EXECUTE=1 aplica)"
  task dedupe: :environment do
    require "csv"

    execute = ENV["EXECUTE"] == "1"
    tenant_scope = ENV["TENANT_ID"].present? ? Tenant.where(id: ENV["TENANT_ID"]) : Tenant.all
    coalesce_skip = %w[id tenant_id created_at updated_at name vista_code cpf_cnpj_digits spouse_cpf_cnpj_digits]

    log_path = Rails.root.join("log", "proprietor_merge_#{Time.current.strftime('%Y%m%d_%H%M')}.csv")
    merged = 0
    deleted = 0
    repointed = 0

    csv = execute ? CSV.open(log_path, "w") : nil
    csv << %w[tenant_id deleted_id canonical_id name vista_code_deleted habitations_repointed] if csv

    tenant_scope.find_each do |tenant|
      Current.set(tenant: tenant) do
        groups = tenant.proprietors.group("lower(trim(name))").having("count(*) > 1").count.keys

        groups.each do |key|
          group = tenant.proprietors.where("lower(trim(name)) = ?", key).order(:id).to_a
          next if group.size < 2

          canonical = group.max_by { |p| [tenant.habitations.where(proprietor_id: p.id).count, -p.id] }
          others = group - [canonical]

          unless execute
            habs = others.sum { |p| tenant.habitations.where(proprietor_id: p.id).count }
            puts "[dry] #{tenant.id} · #{canonical.name.to_s.strip} → mantém ##{canonical.id}, remove #{others.size} (reaponta #{habs} imóveis)"
            merged += 1
            deleted += others.size
            repointed += habs
            next
          end

          ActiveRecord::Base.transaction do
            others.each do |dupe|
              (Proprietor.column_names - coalesce_skip).each do |col|
                canonical[col] = dupe[col] if canonical[col].blank? && dupe[col].present?
              end
              # TODAS as tabelas que referenciam proprietors (FKs do banco)
              count = 0
              %w[habitations habitation_interactions client_interactions crm_appointments client_property_interests].each do |table|
                moved = ActiveRecord::Base.connection.update(
                  ActiveRecord::Base.sanitize_sql_array(
                    ["UPDATE #{table} SET proprietor_id = ? WHERE proprietor_id = ?", canonical.id, dupe.id]
                  )
                )
                count += moved
              end
              repointed += count
              csv << [tenant.id, dupe.id, canonical.id, dupe.name, dupe.vista_code, count]
              dupe.destroy!
              deleted += 1
            end
            canonical.save! if canonical.changed?
            merged += 1
          end
        rescue => e
          puts "grupo #{key} (tenant #{tenant.id}): ERRO #{e.message.first(120)}"
        end
      end
    end

    csv&.close
    puts "-" * 60
    puts "#{execute ? 'EXECUTADO' : 'DRY-RUN'}: #{merged} grupos | #{deleted} duplicados #{execute ? 'removidos' : 'a remover'} | #{repointed} imóveis #{execute ? 'reapontados' : 'a reapontar'}"
    puts "log: #{log_path}" if execute
  end
end

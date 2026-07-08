# Diagnóstico e fusão de proprietários duplicados (herança da base suja do Vista).
#
#   bin/rails proprietors:duplicate_report
#   bin/rails proprietors:duplicate_report TENANT_ID=1
#   bin/rails proprietors:merge_candidates               # DRY-RUN dos candidatos automaticos
#   bin/rails proprietors:merge_candidates EXECUTE=1     # executa candidatos automaticos
#   bin/rails proprietors:merge_candidates EXECUTE=1 RISKS=automatic_candidate,review_required
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

namespace :dwv do
  desc "Reconcilia nome_empreendimento de imóveis DWV cujo condomínio/residencial ficou preso no complemento do endereço. DRY_RUN=true por padrão."
  task reconcile_development_names: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "true"))
    limit = ENV.fetch("LIMIT", "0").to_i
    tenant_id = ENV["TENANT_ID"].presence

    scope = Habitation
            .where(imovel_dwv: "Sim")
            .where("nome_empreendimento IS NULL OR nome_empreendimento = ''")
            .includes(:address)
            .order(:id)
    scope = scope.where(tenant_id: tenant_id) if tenant_id
    scope = scope.limit(limit) if limit.positive?

    total = scope.size
    started_at = Time.current
    puts "[DWV reconcile] início #{started_at.strftime('%Y-%m-%d %H:%M:%S')} | candidatos=#{total} | dry_run=#{dry_run}#{tenant_id ? " | tenant=#{tenant_id}" : ''}"

    stats = { checked: 0, matched: 0, reclassified: 0, complement_cleared: 0, updated: 0, skipped: 0, errors: 0 }

    scope.find_each do |habitation|
      stats[:checked] += 1
      complement = habitation.address&.complemento.presence || habitation.read_attribute(:complemento).presence
      name = Dwv::DevelopmentNameInference.call(complement)

      if name.blank?
        stats[:skipped] += 1
        next
      end

      stats[:matched] += 1

      # Casas avulsas (casa/sobrado/rural/…) têm nome_empreendimento zerado pelo
      # callback do model. Reclassifica para "Casa em Condomínio" — modelagem
      # correta — para o nome persistir.
      needs_reclassify = habitation.categoria != "Casa em Condomínio" &&
                         Habitation.standalone_category_without_development_name?(habitation.categoria) &&
                         habitation.codigo_empreendimento.blank? &&
                         !habitation.empreendimento?
      clears_complement = !complement.match?(/\d/) &&
                          Dwv::DevelopmentNameInference.fold(name) ==
                          Dwv::DevelopmentNameInference.fold(complement)

      puts "  ##{habitation.codigo} (id=#{habitation.id}) empreendimento=\"#{name}\"" \
           "#{needs_reclassify ? ' | => Casa em Condomínio' : ''}" \
           "#{clears_complement ? ' | limpa complemento' : ''}"

      unless dry_run
        Habitation.transaction do
          habitation.categoria = "Casa em Condomínio" if needs_reclassify
          habitation.nome_empreendimento = name
          habitation.save!

          # Invariante: só esvazia o complemento se o nome realmente persistiu
          # (o callback pode tê-lo zerado se a categoria ainda for standalone).
          if clears_complement && habitation.nome_empreendimento.present?
            habitation.update_column(:complemento, nil)
            habitation.address&.update_column(:complemento, nil)
            stats[:complement_cleared] += 1
          end
        end

        if habitation.reload.nome_empreendimento.present?
          stats[:updated] += 1
          stats[:reclassified] += 1 if needs_reclassify
        else
          stats[:skipped] += 1
          warn "  ! nome não persistiu no imóvel id=#{habitation.id} (categoria=#{habitation.categoria})"
        end
      end
    rescue => e
      stats[:errors] += 1
      warn "  ! erro no imóvel id=#{habitation.id}: #{e.class} #{e.message}"
    end

    elapsed = (Time.current - started_at).round(1)
    puts "[DWV reconcile] fim | #{stats.map { |k, v| "#{k}=#{v}" }.join(' | ')} | #{elapsed}s"
    puts "[DWV reconcile] DRY_RUN ativo — nada foi gravado. Rode com DRY_RUN=false para aplicar." if dry_run
  end
end

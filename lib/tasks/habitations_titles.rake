# frozen_string_literal: true

namespace :data do
  desc "Backfill titulo_anuncio via Habitations::TitleComposer. DRY-RUN by default; APPLY=true persists (with backup table). TENANT_ID required."
  task backfill_habitation_titles: :environment do
    tenant_id = ENV["TENANT_ID"].to_s.strip
    abort "TENANT_ID required (ex.: TENANT_ID=1)" if tenant_id.blank?

    apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch("APPLY", "false"))
    limit = ENV["LIMIT"].to_i.positive? ? ENV["LIMIT"].to_i : nil
    backup_table = ENV.fetch("BACKUP_TABLE", "habitations_titles_backup_#{Date.current.strftime('%Y%m%d')}")

    tenant = Tenant.find(tenant_id)
    scope = tenant.habitations.where.not(nome_empreendimento: [nil, ""]).order(:id)
    scope = scope.limit(limit) if limit

    if apply
      quoted = ActiveRecord::Base.connection.quote_table_name(backup_table)
      ActiveRecord::Base.connection.execute(
        "CREATE TABLE #{quoted} AS SELECT id, titulo_anuncio, meta_title FROM habitations WHERE tenant_id = #{tenant.id}"
      )
      puts "backup: #{backup_table}"
    end

    stats = Hash.new(0)
    samples = []
    scope.includes(:address).find_each do |habitation|
      result = Habitations::TitleComposer.compose(habitation)
      if result.title.nil?
        stats["skip:#{result.skip_reason}"] += 1
        next
      end
      if habitation.titulo_anuncio.to_s.squish == result.title
        stats["noop:already_composed"] += 1
        next
      end

      samples << [habitation.id, habitation.codigo, habitation.titulo_anuncio, result.title] if samples.size < 20
      # update_columns: pula callbacks/auditoria de propósito (backfill em massa);
      # slugs não regeneram em mudança de título (should_generate_new_friendly_id?).
      habitation.update_columns(titulo_anuncio: result.title, meta_title: result.title, updated_at: Time.current) if apply
      stats[result.tier == :over_limit ? "warn:over_limit" : "composed:#{result.tier}"] += 1
    end

    puts "tenant: #{tenant.id} (#{tenant.name})"
    puts "mode: #{apply ? 'APPLY' : 'DRY-RUN'}"
    stats.sort.each { |key, count| puts "  #{key}: #{count}" }
    puts "samples (id | codigo | atual => novo):"
    samples.each { |id, codigo, old_title, new_title| puts "  #{id} | #{codigo} | #{old_title} => #{new_title}" }
  end
end

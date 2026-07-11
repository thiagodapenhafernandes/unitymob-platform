# frozen_string_literal: true

# pg_stat_statements mostrou materializações integrais do catálogo por tenant,
# mas não informa o call site Ruby. Este tracer observa somente essa forma
# exata, sem binds/dados, e limita cada origem a um log por cinco minutos.
Rails.application.config.after_initialize do
  pattern = /\ASELECT "habitations"\.\* FROM "habitations" WHERE "habitations"\."tenant_id" = \$\d+\z/
  throttle = ActiveSupport::Cache::MemoryStore.new

  ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
    sql = payload[:sql].to_s.squish
    next unless sql.match?(pattern)

    location = caller_locations.find do |frame|
      path = frame.absolute_path.to_s
      path.start_with?(Rails.root.join("app").to_s, Rails.root.join("lib").to_s)
    end
    next if location.blank?

    key = "full_habitation_load:#{location.path}:#{location.lineno}"
    next if throttle.exist?(key)

    throttle.write(key, true, expires_in: 5.minutes)
    Rails.logger.warn(
      "[PERF_FULL_HABITATION_LOAD] source=#{location.path.delete_prefix("#{Rails.root}/")}:#{location.lineno}"
    )
  end
end

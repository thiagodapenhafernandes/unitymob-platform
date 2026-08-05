class CopyLegacyIntegrationSettingsToDefaultTenant < ActiveRecord::Migration[7.1]
  EXACT_KEYS = %w[
    loft_enabled
    loft_host
    loft_token
    loft_preserve_manual_fields
    loft_sync_batch_size
    loft_images_sync_limit
    loft_poll_processing_interval_ms
    loft_poll_idle_interval_ms
    loft_poll_slow_interval_ms
    loft_sync_status
    loft_sync_progress
    loft_last_sync_message
    loft_last_sync_at
    loft_sync_history
    dwv_enabled
    dwv_api_token
    dwv_base_url
    dwv_sync_limit
    dwv_sync_max_pages
    dwv_request_pause_seconds
    dwv_poll_processing_interval_ms
    dwv_poll_idle_interval_ms
    dwv_poll_slow_interval_ms
    dwv_sync_status
    dwv_sync_progress
    dwv_last_sync_message
    dwv_last_sync_at
    dwv_last_error_summary
    dwv_sync_history
    openai_api_key
    openai_model
    openai_property_enrichment_prompt
    openai_property_search_api_key
    openai_property_search_model
    openai_property_search_transcription_model
    seo_ai_strategy_prompt
    openai_batch_status
    openai_batch_progress
    openai_batch_message
    openai_batch_last_at
    photography_schedule_url
    lead_share_tracking_days
    whatsapp_site_routing
  ].freeze

  KEY_PREFIXES = %w[
    google_sheets.captacoes.
    tracking.
    image_migration.
    vista_agents_sync_
    vista_brokers_backfill_
  ].freeze

  ENV_SEEDS = {
    "loft_host" => ["VISTA_HOST", "Host da API Vista/Loft da Salute"],
    "loft_token" => ["VISTA_KEY", "Token da API Vista/Loft da Salute"],
    "openai_api_key" => ["OPENAI_API_KEY", "Token OpenAI da Salute"]
  }.freeze

  def up
    return unless table_exists?(:settings) && column_exists?(:settings, :tenant_id)
    return unless table_exists?(:tenants)

    tenant_id = default_tenant_id
    return if tenant_id.blank?

    copy_global_rows!(tenant_id)
    copy_env_values!(tenant_id)
  end

  def down
    # Intencionalmente não remove dados: a migração é uma cópia de preservação
    # para evitar perda de configuração da Salute ao tornar integrações estritas.
  end

  private

  def default_tenant_id
    slug = ENV.fetch("DEFAULT_TENANT_SLUG", "default")
    select_value(<<~SQL.squish) || select_value("SELECT id FROM tenants ORDER BY id ASC LIMIT 1")
      SELECT id FROM tenants
      WHERE slug = #{connection.quote(slug)}
      ORDER BY id ASC LIMIT 1
    SQL
  end

  def copy_global_rows!(tenant_id)
    conditions = [
      "key IN (#{EXACT_KEYS.map { |key| connection.quote(key) }.join(', ')})",
      *KEY_PREFIXES.map { |prefix| "key LIKE #{connection.quote("#{prefix}%")}" }
    ].join(" OR ")

    execute <<~SQL.squish
      INSERT INTO settings (tenant_id, key, value, description, created_at, updated_at)
      SELECT #{connection.quote(tenant_id)}, key, value, description, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM settings global_settings
      WHERE tenant_id IS NULL
        AND (#{conditions})
        AND NOT EXISTS (
          SELECT 1
          FROM settings tenant_settings
          WHERE tenant_settings.tenant_id = #{connection.quote(tenant_id)}
            AND tenant_settings.key = global_settings.key
        )
    SQL
  end

  def copy_env_values!(tenant_id)
    ENV_SEEDS.each do |key, (env_name, description)|
      value = ENV[env_name].to_s.strip
      next if value.blank?
      next if tenant_setting_exists?(tenant_id, key)

      execute <<~SQL.squish
        INSERT INTO settings (tenant_id, key, value, description, created_at, updated_at)
        VALUES (
          #{connection.quote(tenant_id)},
          #{connection.quote(key)},
          #{connection.quote(value)},
          #{connection.quote(description)},
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        )
      SQL
    end
  end

  def tenant_setting_exists?(tenant_id, key)
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM settings
      WHERE tenant_id = #{connection.quote(tenant_id)}
        AND key = #{connection.quote(key)}
      LIMIT 1
    SQL
  end
end

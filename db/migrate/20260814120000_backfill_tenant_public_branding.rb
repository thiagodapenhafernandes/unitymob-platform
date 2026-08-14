class BackfillTenantPublicBranding < ActiveRecord::Migration[7.1]
  class TenantRecord < ActiveRecord::Base
    self.table_name = "tenants"
  end

  class LayoutSettingRecord < ActiveRecord::Base
    self.table_name = "layout_settings"
  end

  class TenantDomainRecord < ActiveRecord::Base
    self.table_name = "tenant_domains"
  end

  class SettingRecord < ActiveRecord::Base
    self.table_name = "settings"
  end

  class HabitationRecord < ActiveRecord::Base
    self.table_name = "habitations"
  end

  class RichTextRecord < ActiveRecord::Base
    self.table_name = "action_text_rich_texts"
  end

  class SeoSettingRecord < ActiveRecord::Base
    self.table_name = "seo_settings"
  end

  class SeoFocusKeywordRecord < ActiveRecord::Base
    self.table_name = "seo_focus_keywords"
  end

  class SeoPageVisitRecord < ActiveRecord::Base
    self.table_name = "seo_page_visits"
  end

  class SeoConversionEventRecord < ActiveRecord::Base
    self.table_name = "seo_conversion_events"
  end

  class PublicFormRecord < ActiveRecord::Base
    self.table_name = "public_forms"
  end

  TEXT_COLUMNS_BY_TABLE = {
    "seo_settings" => %w[
      page_name meta_title meta_description meta_keywords og_image canonical_url canonical_path
      og_title og_description intro_text ai_summary ai_insights
    ],
    "seo_page_visits" => %w[path],
    "seo_conversion_events" => %w[path source_path metadata],
    "public_forms" => %w[name title subtitle submit_label success_message modal_config]
  }.freeze

  def up
    TenantRecord.find_each do |tenant|
      identity = tenant_identity(tenant)

      backfill_action_text_for(tenant, identity)
      backfill_seo_settings_for(tenant, identity)
      backfill_seo_keywords_for(tenant, identity)
      backfill_seo_page_visits_for(tenant, identity)
      backfill_seo_conversion_events_for(tenant, identity)
      backfill_public_forms_for(tenant, identity)
    end
  end

  def down
    # Limpeza de marca em dados de produção. Não reintroduzimos referências de outra conta.
  end

  private

  def tenant_identity(tenant)
    layout_name = LayoutSettingRecord.where(tenant_id: tenant.id).pick(:site_name).to_s.squish
    brand = layout_name.presence || tenant.name.to_s.squish.presence || "Imobiliária"
    brand = tenant.name.to_s.squish if brand.match?(/salute/i) && tenant.name.to_s !~ /salute/i

    {
      brand: brand.presence || "Imobiliária",
      city: primary_city_for(tenant),
      host: primary_host_for(tenant)
    }
  end

  def primary_city_for(tenant)
    configured_city = tenant_setting_value(tenant, "public_site.profile.primary_city").to_s.squish
    return configured_city if configured_city.present?

    city_from_habitations(tenant).presence || "sua região"
  end

  def tenant_setting_value(tenant, key)
    return unless table_exists?(:settings)

    scope = SettingRecord.where(key: key)
    scope = scope.where(tenant_id: tenant.id) if column_exists?(:settings, :tenant_id)
    scope.pick(:value)
  end

  def city_from_habitations(tenant)
    return unless table_exists?(:habitations)

    if table_exists?(:addresses) && column_exists?(:addresses, :habitation_id) && column_exists?(:addresses, :cidade)
      sql = sanitize_sql_array([<<~SQL, tenant.id])
        SELECT COALESCE(NULLIF(TRIM(addresses.cidade), ''), NULLIF(TRIM(habitations.cidade), '')) AS city
          FROM habitations
          LEFT JOIN addresses ON addresses.habitation_id = habitations.id
         WHERE habitations.tenant_id = ?
           AND COALESCE(NULLIF(TRIM(addresses.cidade), ''), NULLIF(TRIM(habitations.cidade), '')) IS NOT NULL
         GROUP BY 1
         ORDER BY COUNT(*) DESC
         LIMIT 1
      SQL
    else
      sql = sanitize_sql_array([<<~SQL, tenant.id])
        SELECT NULLIF(TRIM(cidade), '') AS city
          FROM habitations
         WHERE tenant_id = ?
           AND NULLIF(TRIM(cidade), '') IS NOT NULL
         GROUP BY 1
         ORDER BY COUNT(*) DESC
         LIMIT 1
      SQL
    end

    select_value(sql)
  end

  def primary_host_for(tenant)
    host = primary_tenant_domain_for(tenant)
    return host if host.present?

    app_host_from_env if TenantRecord.count == 1
  end

  def primary_tenant_domain_for(tenant)
    return unless table_exists?(:tenant_domains)

    scope = TenantDomainRecord.where(tenant_id: tenant.id)
    scope = scope.where(active: true) if column_exists?(:tenant_domains, :active)
    scope = scope.order(primary_domain: :desc) if column_exists?(:tenant_domains, :primary_domain)

    scope.order(hostname: :asc).pick(:hostname)
      .to_s
      .squish
      .presence
  end

  def app_host_from_env
    value = ENV["APP_HOST"].to_s.squish
    return if value.blank?

    uri = URI.parse(value.start_with?("http") ? value : "https://#{value}")
    uri.host.presence
  rescue URI::InvalidURIError
    nil
  end

  def backfill_action_text_for(tenant, identity)
    return unless table_exists?(:action_text_rich_texts) && table_exists?(:habitations)

    RichTextRecord
      .joins("INNER JOIN habitations ON habitations.id = action_text_rich_texts.record_id")
      .where(record_type: "Habitation", name: %w[descricao_web meta_description])
      .where(habitations: { tenant_id: tenant.id })
      .where("action_text_rich_texts.body ILIKE '%salute%' OR action_text_rich_texts.body ILIKE '%saluteimoveis%'")
      .find_each do |record|
        replace_record_columns(record, %w[body], identity)
      end
  end

  def backfill_seo_settings_for(tenant, identity)
    return unless table_exists?(:seo_settings) && column_exists?(:seo_settings, :tenant_id)

    columns = existing_text_columns("seo_settings")
    return if columns.blank?

    SeoSettingRecord.where(tenant_id: tenant.id).find_each do |record|
      replace_record_columns(record, columns, identity)
    end
  end

  def backfill_seo_keywords_for(tenant, identity)
    return unless table_exists?(:seo_focus_keywords) && table_exists?(:seo_settings)

    SeoFocusKeywordRecord
      .joins("INNER JOIN seo_settings ON seo_settings.id = seo_focus_keywords.seo_setting_id")
      .where(seo_settings: { tenant_id: tenant.id })
      .where("seo_focus_keywords.keyword ILIKE '%salute%'")
      .find_each do |record|
        next unless record.has_attribute?(:keyword)

        replaced = tenantized_text(record.keyword, identity).to_s.downcase
        record.update_columns(keyword: replaced, updated_at: Time.current) if replaced != record.keyword
      end
  end

  def backfill_seo_page_visits_for(tenant, identity)
    return unless table_exists?(:seo_page_visits) && table_exists?(:seo_settings)

    columns = existing_text_columns("seo_page_visits")
    return if columns.blank?

    SeoPageVisitRecord
      .joins("INNER JOIN seo_settings ON seo_settings.id = seo_page_visits.seo_setting_id")
      .where(seo_settings: { tenant_id: tenant.id })
      .find_each do |record|
        replace_record_columns(record, columns, identity)
      end
  end

  def backfill_seo_conversion_events_for(tenant, identity)
    return unless table_exists?(:seo_conversion_events)

    columns = existing_text_columns("seo_conversion_events")
    return if columns.blank?

    scoped_ids = conversion_event_ids_for(tenant)
    return if scoped_ids.blank?

    SeoConversionEventRecord.where(id: scoped_ids).find_each do |record|
      replace_record_columns(record, columns, identity)
    end
  end

  def conversion_event_ids_for(tenant)
    ids = []
    if table_exists?(:seo_settings) && column_exists?(:seo_conversion_events, :seo_setting_id)
      ids.concat select_values(sanitize_sql_array([<<~SQL, tenant.id]))
        SELECT seo_conversion_events.id
          FROM seo_conversion_events
          INNER JOIN seo_settings ON seo_settings.id = seo_conversion_events.seo_setting_id
         WHERE seo_settings.tenant_id = ?
      SQL
    end

    if table_exists?(:habitations) && column_exists?(:seo_conversion_events, :habitation_id)
      ids.concat select_values(sanitize_sql_array([<<~SQL, tenant.id]))
        SELECT seo_conversion_events.id
          FROM seo_conversion_events
          INNER JOIN habitations ON habitations.id = seo_conversion_events.habitation_id
         WHERE habitations.tenant_id = ?
      SQL
    end

    if TenantRecord.count == 1
      ids.concat select_values(<<~SQL)
        SELECT id
          FROM seo_conversion_events
         WHERE metadata::text ILIKE '%salute%'
            OR source_path ILIKE '%salute%'
            OR path ILIKE '%salute%'
      SQL
    end

    ids.uniq
  end

  def backfill_public_forms_for(tenant, identity)
    return unless table_exists?(:public_forms) && column_exists?(:public_forms, :tenant_id)

    columns = existing_text_columns("public_forms")
    return if columns.blank?

    PublicFormRecord.where(tenant_id: tenant.id).find_each do |record|
      replace_record_columns(record, columns, identity)
    end
  end

  def replace_record_columns(record, columns, identity)
    updates = {}

    columns.each do |column|
      next unless record.has_attribute?(column)

      original = record.public_send(column)
      replaced = tenantized_value(original, identity)
      updates[column] = replaced if replaced != original
    end

    return if updates.blank?

    updates["updated_at"] = Time.current if record.has_attribute?(:updated_at)
    record.update_columns(updates)
  end

  def existing_text_columns(table)
    TEXT_COLUMNS_BY_TABLE.fetch(table, []).select do |column|
      column_exists?(table, column)
    end
  end

  def tenantized_value(value, identity)
    case value
    when Hash
      value.transform_values { |inner| tenantized_value(inner, identity) }
    when Array
      value.map { |inner| tenantized_value(inner, identity) }
    else
      tenantized_text(value, identity)
    end
  end

  def tenantized_text(value, identity)
    return value unless value.is_a?(String)

    brand = identity.fetch(:brand)
    city = identity.fetch(:city)
    host = identity[:host]
    url = host.present? ? "https://#{host}" : nil

    text = value.dup
    text.gsub!(/A\s+Salute Imóveis está localizada em Balneário Camboriú,\s*Santa Catarina\.?/i, "A #{brand} atua em #{city} e região.")
    text.gsub!(/Salute Imóveis/i, brand)
    text.gsub!(/Festival Salute/i, "Oportunidades")
    text.gsub!(/Seleção Salute/i, "Seleção #{brand}")
    text.gsub!(/Por que a Salute/i, "Por que a #{brand}")
    text.gsub!(/A Salute\b/i, "A #{brand}")
    text.gsub!(/especialista Salute/i, "especialista #{brand}")
    text.gsub!(%r{/salute-parcerias}i, "/parcerias")
    text.gsub!(/festival-salute-2026/i, "oportunidades")

    if url.present?
      text.gsub!(%r{https?://(?:www\.)?saluteimoveis\.com\.br}i, url)
      text.gsub!(%r{https?://(?:www\.)?saluteimoveis\.com(?!\.br)}i, url)
      text.gsub!(/www\.saluteimoveis\.com\.br/i, host)
      text.gsub!(/www\.saluteimoveis\.com(?!\.br)/i, host)
      text.gsub!(/saluteimoveis\.com\.br/i, host)
      text.gsub!(/saluteimoveis\.com(?!\.br)/i, host)
    end

    text
  end

  def sanitize_sql_array(array)
    ActiveRecord::Base.send(:sanitize_sql_array, array)
  end
end

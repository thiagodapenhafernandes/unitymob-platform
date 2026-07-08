class ScopePropertySettingsToTenant < ActiveRecord::Migration[7.1]
  # property_settings era uma linha GLOBAL: o fluxo de revisão/marca d'água
  # configurado por uma conta valia para todas (vazamento de config).
  # Passa a ser 1 linha POR TENANT. Backfill preserva comportamento: a linha
  # original vai para o tenant mais antigo e é CLONADA para os demais
  # (fallback_admin_user não clona — é usuário de outra conta).
  def up
    unless column_exists?(:property_settings, :tenant_id)
      add_reference :property_settings, :tenant, foreign_key: true
    end

    unless index_exists?(:property_settings, :tenant_id, name: :idx_property_settings_on_tenant_unique)
      add_index :property_settings, :tenant_id, unique: true,
                where: "tenant_id IS NOT NULL", name: :idx_property_settings_on_tenant_unique
    end

    original_id = select_value("SELECT id FROM property_settings ORDER BY id LIMIT 1")
    return if original_id.blank?

    first_tenant_id = select_value("SELECT id FROM tenants ORDER BY id LIMIT 1")
    return if first_tenant_id.blank?

    execute <<~SQL
      UPDATE property_settings SET tenant_id = #{first_tenant_id.to_i}
       WHERE id = #{original_id.to_i} AND tenant_id IS NULL
    SQL

    execute <<~SQL
      INSERT INTO property_settings
        (tenant_id, watermark_position, watermark_size_percentage, watermark_opacity_percentage,
         broker_capture_layer_enabled, required_broker_intake_checks, returnable_intake_edit_sections,
         broker_capture_fallback_admin_user_id, notify_internal_review_events, notify_email_review_events,
         review_notification_emails, created_at, updated_at)
      SELECT t.id, ps.watermark_position, ps.watermark_size_percentage, ps.watermark_opacity_percentage,
             ps.broker_capture_layer_enabled, ps.required_broker_intake_checks, ps.returnable_intake_edit_sections,
             NULL, ps.notify_internal_review_events, ps.notify_email_review_events,
             ps.review_notification_emails, NOW(), NOW()
        FROM tenants t
       CROSS JOIN property_settings ps
       WHERE ps.id = #{original_id.to_i}
         AND t.id <> #{first_tenant_id.to_i}
         AND NOT EXISTS (SELECT 1 FROM property_settings x WHERE x.tenant_id = t.id)
    SQL

    # Marca d'água: os clones apontam para o MESMO blob (ActiveStorage permite).
    original = PropertySetting.find_by(id: original_id)
    if original&.watermark_image&.attached?
      blob = original.watermark_image.blob
      PropertySetting.where.not(id: original_id).find_each do |setting|
        setting.watermark_image.attach(blob) unless setting.watermark_image.attached?
      end
    end
  end

  def down
    # Mantém só a linha do tenant mais antigo como global de novo.
    first_tenant_id = select_value("SELECT id FROM tenants ORDER BY id LIMIT 1")
    if first_tenant_id.present?
      execute "DELETE FROM property_settings WHERE tenant_id IS NOT NULL AND tenant_id <> #{first_tenant_id.to_i}"
    end
    remove_index :property_settings, name: :idx_property_settings_on_tenant_unique if index_exists?(:property_settings, :tenant_id, name: :idx_property_settings_on_tenant_unique)
    remove_reference :property_settings, :tenant, foreign_key: true if column_exists?(:property_settings, :tenant_id)
  end
end

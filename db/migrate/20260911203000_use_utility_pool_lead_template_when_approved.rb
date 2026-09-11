class UseUtilityPoolLeadTemplateWhenApproved < ActiveRecord::Migration[7.1]
  POOL_MAPPING = {
    "1" => "broker_name",
    "2" => "lead_origin",
    "3" => "lead_name",
    "4" => "lead_phone_or_link",
    "5" => "lead_email_or_link",
    "6" => "lead_other_or_link"
  }.freeze

  def up
    mapping_json = connection.quote({ variable_mapping: POOL_MAPPING }.to_json)

    execute <<~SQL.squish
      WITH approved_templates AS (
        SELECT DISTINCT ON (tenant_id) tenant_id, id AS whatsapp_template_id
        FROM whatsapp_templates
        WHERE name = 'lead_pool_alert_utility'
          AND language = 'pt_BR'
          AND status = 'APPROVED'
          AND category = 'UTILITY'
        ORDER BY tenant_id, updated_at DESC, id DESC
      )
      UPDATE notification_template_settings settings
      SET whatsapp_template_id = approved_templates.whatsapp_template_id,
          active = TRUE,
          metadata = CASE
            WHEN settings.metadata ? 'variable_mapping' THEN settings.metadata
            ELSE #{mapping_json}::jsonb
          END,
          updated_at = CURRENT_TIMESTAMP
      FROM approved_templates
      WHERE settings.tenant_id = approved_templates.tenant_id
        AND settings.channel = 'whatsapp'
        AND settings.purpose = 'lead_distribution_broker_pool'
        AND settings.whatsapp_template_id IS DISTINCT FROM approved_templates.whatsapp_template_id
    SQL

    execute <<~SQL.squish
      WITH approved_templates AS (
        SELECT DISTINCT ON (tenant_id) tenant_id, id AS whatsapp_template_id
        FROM whatsapp_templates
        WHERE name = 'lead_pool_alert_utility'
          AND language = 'pt_BR'
          AND status = 'APPROVED'
          AND category = 'UTILITY'
        ORDER BY tenant_id, updated_at DESC, id DESC
      )
      INSERT INTO notification_template_settings (
        tenant_id,
        whatsapp_template_id,
        channel,
        purpose,
        active,
        metadata,
        created_at,
        updated_at
      )
      SELECT
        approved_templates.tenant_id,
        approved_templates.whatsapp_template_id,
        'whatsapp',
        'lead_distribution_broker_pool',
        TRUE,
        #{mapping_json}::jsonb,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM approved_templates
      WHERE NOT EXISTS (
        SELECT 1
        FROM notification_template_settings settings
        WHERE settings.tenant_id = approved_templates.tenant_id
          AND settings.channel = 'whatsapp'
          AND settings.purpose = 'lead_distribution_broker_pool'
      )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

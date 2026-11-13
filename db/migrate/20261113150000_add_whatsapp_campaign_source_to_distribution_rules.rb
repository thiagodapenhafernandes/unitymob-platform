class AddWhatsappCampaignSourceToDistributionRules < ActiveRecord::Migration[7.1]
  def up
    add_column :distribution_rules, :source_whatsapp_campaign, :boolean, default: false, null: false

    # Mantém os destinos já escolhidos nas campanhas de cada conta.
    execute <<~SQL
      UPDATE distribution_rules AS rule
      SET source_whatsapp_campaign = TRUE
      WHERE EXISTS (
        SELECT 1
        FROM whatsapp_campaigns AS campaign
        CROSS JOIN LATERAL jsonb_array_elements(
          CASE jsonb_typeof(campaign.response_decisions -> 'buttons')
            WHEN 'array' THEN campaign.response_decisions -> 'buttons'
            WHEN 'object' THEN (
              SELECT COALESCE(jsonb_agg(value), '[]'::jsonb)
              FROM jsonb_each(campaign.response_decisions -> 'buttons')
            )
            ELSE '[]'::jsonb
          END
        ) AS decision
        WHERE campaign.tenant_id = rule.tenant_id
          AND decision ->> 'action' = 'generate_lead'
          AND decision ->> 'distribution_rule_id' = rule.id::text
      )
    SQL
  end

  def down
    remove_column :distribution_rules, :source_whatsapp_campaign
  end
end

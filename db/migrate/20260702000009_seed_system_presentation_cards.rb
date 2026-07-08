class SeedSystemPresentationCards < ActiveRecord::Migration[7.1]
  # 1 template de sistema por tenant (idempotente) + limpeza dos "Padrão"
  # pessoais auto-criados que nunca foram usados em envio. Os "Padrão" com
  # envios carimbados são preservados como cartões pessoais (nada se perde).
  def up
    execute <<~SQL
      INSERT INTO presentation_cards (tenant_id, admin_user_id, label, greeting, use_photo, active, position, system, created_at, updated_at)
      SELECT t.id, NULL, 'Padrão',
             'Olá! Sou {nome}, corretor(a) responsável pelo seu atendimento. Como posso ajudar?',
             TRUE, TRUE, 0, TRUE, NOW(), NOW()
      FROM tenants t
      WHERE NOT EXISTS (
        SELECT 1 FROM presentation_cards pc WHERE pc.tenant_id = t.id AND pc.system = TRUE
      )
    SQL

    execute <<~SQL
      DELETE FROM presentation_cards pc
      WHERE pc.system = FALSE
        AND pc.label = 'Padrão'
        AND NOT EXISTS (SELECT 1 FROM whatsapp_messages wm WHERE wm.presentation_card_id = pc.id)
    SQL
  end

  def down
    execute <<~SQL
      DELETE FROM presentation_cards pc
      WHERE pc.system = TRUE
        AND NOT EXISTS (SELECT 1 FROM whatsapp_messages wm WHERE wm.presentation_card_id = pc.id)
    SQL
  end
end

class BackfillDefaultPresentationCards < ActiveRecord::Migration[7.1]
  # Idempotente: cria o cartão "Padrão" para corretores que ainda não têm
  # NENHUM cartão. SQL puro para não depender de código da aplicação.
  def up
    execute <<~SQL
      INSERT INTO presentation_cards (tenant_id, admin_user_id, label, greeting, use_photo, active, position, created_at, updated_at)
      SELECT
        au.tenant_id,
        au.id,
        'Padrão',
        'Olá! Sou ' || COALESCE(NULLIF(TRIM(au.name), ''), 'o corretor') || ', corretor(a) responsável pelo seu atendimento. Como posso ajudar?',
        TRUE,
        TRUE,
        0,
        NOW(),
        NOW()
      FROM admin_users au
      WHERE au.tenant_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM presentation_cards pc WHERE pc.admin_user_id = au.id
        )
    SQL
  end

  def down
    # Remove apenas cartões "Padrão" nunca usados em envios (mensagens carimbadas
    # apontando para eles são preservadas ao não excluir esses cartões).
    execute <<~SQL
      DELETE FROM presentation_cards pc
      WHERE pc.label = 'Padrão'
        AND NOT EXISTS (
          SELECT 1 FROM whatsapp_messages wm WHERE wm.presentation_card_id = pc.id
        )
    SQL
  end
end

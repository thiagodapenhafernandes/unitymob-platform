class NormalizeDammedLeadsWithOwner < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE leads
      SET status = 'Em Atendimento',
          updated_at = CURRENT_TIMESTAMP
      WHERE admin_user_id IS NOT NULL
        AND status = 'Represado'
    SQL
  end

  def down
    # Sem reversao segura: depois da normalizacao nao ha como saber se o lead
    # estava represado por erro antigo ou se foi alterado manualmente depois.
  end
end

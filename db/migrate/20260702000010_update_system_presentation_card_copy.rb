class UpdateSystemPresentationCardCopy < ActiveRecord::Migration[7.1]
  NEW_COPY = "Oi! 👋 Aqui é o {nome}, da {empresa}. A partir de agora eu cuido do seu atendimento — pode falar comigo por aqui. Como posso ajudar?".freeze
  OLD_COPY = "Olá! Sou {nome}, corretor(a) responsável pelo seu atendimento. Como posso ajudar?".freeze

  # Idempotente e conservador: só atualiza templates de SISTEMA que ainda estão
  # com a copy antiga intocada (edições do admin são preservadas).
  def up
    execute ActiveRecord::Base.sanitize_sql([<<~SQL, NEW_COPY, OLD_COPY])
      UPDATE presentation_cards SET greeting = ?, updated_at = NOW()
      WHERE system = TRUE AND greeting = ?
    SQL
  end

  def down
    execute ActiveRecord::Base.sanitize_sql([<<~SQL, OLD_COPY, NEW_COPY])
      UPDATE presentation_cards SET greeting = ?, updated_at = NOW()
      WHERE system = TRUE AND greeting = ?
    SQL
  end
end

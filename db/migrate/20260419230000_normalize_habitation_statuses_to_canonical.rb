class NormalizeHabitationStatusesToCanonical < ActiveRecord::Migration[7.1]
  # Normaliza valores de status para a lista canônica de 10 opções:
  # Venda, Aluguel, Diária, Pendente, Lançamento, Suspenso,
  # Alugado imobiliária, Alugado terceiros, Vendido imobiliária, Vendido terceiros
  #
  # Cobre case mixed ("PENDENTE"), sinônimos ("Locação" -> "Aluguel"),
  # status fora da lista ("Venda e Aluguel" -> "Venda").
  MAPPING = {
    "PENDENTE"            => "Pendente",
    "Locação"             => "Aluguel",
    "Locacao"             => "Aluguel",
    "Venda e Aluguel"     => "Venda",
    "Vendido Imobiliária" => "Vendido imobiliária",
    "Vendido Imobiliaria" => "Vendido imobiliária",
    "Vendido Terceiros"   => "Vendido terceiros",
    "Alugado Imobiliária" => "Alugado imobiliária",
    "Alugado Imobiliaria" => "Alugado imobiliária",
    "Alugado Terceiros"   => "Alugado terceiros"
  }.freeze

  CANONICAL_STATUSES = [
    "Venda", "Aluguel", "Diária", "Pendente", "Lançamento", "Suspenso",
    "Alugado imobiliária", "Alugado terceiros",
    "Vendido imobiliária", "Vendido terceiros"
  ].freeze

  def up
    # 1) Atualiza habitations.status
    MAPPING.each do |old_value, new_value|
      execute <<~SQL.squish
        UPDATE habitations
        SET status = #{ActiveRecord::Base.connection.quote(new_value)}
        WHERE status = #{ActiveRecord::Base.connection.quote(old_value)}
      SQL
    end

    # 2) Atualiza portal_integrations.allowed_statuses (text[]) — substitui
    #    cada valor antigo pelo canônico dentro do array.
    MAPPING.each do |old_value, new_value|
      execute <<~SQL.squish
        UPDATE portal_integrations
        SET allowed_statuses = array_replace(
          allowed_statuses,
          #{ActiveRecord::Base.connection.quote(old_value)},
          #{ActiveRecord::Base.connection.quote(new_value)}
        )
        WHERE #{ActiveRecord::Base.connection.quote(old_value)} = ANY(allowed_statuses)
      SQL
    end

    # 3) Remove duplicatas que possam ter surgido após substituição
    execute <<~SQL.squish
      UPDATE portal_integrations
      SET allowed_statuses = (SELECT array_agg(DISTINCT s) FROM unnest(allowed_statuses) AS s)
      WHERE allowed_statuses IS NOT NULL
    SQL

    say "Status normalizados. Distribuição final:"
    rows = execute("SELECT status, COUNT(*) AS n FROM habitations WHERE status IS NOT NULL AND status <> '' GROUP BY status ORDER BY n DESC")
    rows.each { |r| say "  #{r['status']}: #{r['n']}", true }
  end

  def down
    # Não reverte — normalização é one-way. Os valores antigos eram inconsistentes.
    raise ActiveRecord::IrreversibleMigration
  end
end

class AddPrecoAtualizadoEmToHabitations < ActiveRecord::Migration[7.1]
  def up
    unless column_exists?(:habitations, :preco_atualizado_em)
      add_column :habitations, :preco_atualizado_em, :datetime
    end

    # Backfill: usa a data da última alteração de preço já registrada no audit
    # log, para o badge "preço atualizado há X dias" já valer para o acervo atual.
    say_with_time "Backfill preco_atualizado_em pelo audit log" do
      execute(<<~SQL)
        UPDATE habitations h
        SET preco_atualizado_em = sub.last_change
        FROM (
          SELECT habitation_id, MAX(created_at) AS last_change
          FROM habitation_audit_logs
          WHERE changed_fields && ARRAY['valor_venda_cents', 'valor_locacao_cents']::text[]
          GROUP BY habitation_id
        ) sub
        WHERE sub.habitation_id = h.id
          AND h.preco_atualizado_em IS NULL
      SQL
    end
  end

  def down
    remove_column :habitations, :preco_atualizado_em
  end
end

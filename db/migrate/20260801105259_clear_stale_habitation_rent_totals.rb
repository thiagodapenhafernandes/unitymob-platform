class ClearStaleHabitationRentTotals < ActiveRecord::Migration[7.1]
  PLACEHOLDER_TAX_CENTS = [0, 1, 100].freeze

  def up
    say_with_time "Clearing stale habitation rent totals" do
      execute <<~SQL.squish
        UPDATE #{quote_table_name(:habitations)}
           SET valor_total_aluguel_cents = NULL
         WHERE valor_locacao_cents > 0
           AND valor_total_aluguel_cents > 0
           AND valor_total_aluguel_cents < valor_locacao_cents
           AND COALESCE(valor_condominio_cents, 0) IN (#{PLACEHOLDER_TAX_CENTS.join(", ")})
           AND COALESCE(valor_iptu_cents, 0) IN (#{PLACEHOLDER_TAX_CENTS.join(", ")})
      SQL
    end
  end

  def down
    # Data hygiene only. The stale value cannot be reconstructed safely.
  end
end

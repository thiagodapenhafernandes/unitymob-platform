class MarkDualSaleRentHabitations < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE habitations
      SET status = 'Venda e Aluguel', updated_at = CURRENT_TIMESTAMP
      WHERE COALESCE(valor_venda_cents, 0) > 0
        AND COALESCE(valor_locacao_cents, 0) > 0
        AND tenant_id IN (
          SELECT tenants.id
          FROM tenants
          LEFT JOIN tenant_domains ON tenant_domains.tenant_id = tenants.id
          WHERE tenants.id = 72
            OR LOWER(tenants.name) = LOWER('Conexão Imobiliária')
            OR LOWER(tenant_domains.hostname) = LOWER('app.conexaobc.com')
        )
        AND NOT (LOWER(unaccent(COALESCE(status, ''))) ~ '(suspenso|alugado|vendido|pendente|diaria|temporada)')
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

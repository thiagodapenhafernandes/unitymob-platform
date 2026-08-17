class SeedLeadArchiveReasons < ActiveRecord::Migration[7.1]
  REASONS = [
    "Alugado", "Apenas pesquisando", "Avaliação baixa na troca", "Cliente não respondeu",
    "Compra adiada", "Contato Inválido", "Corretor Parceiro", "Falta de produto",
    "Fechou negócio em outro lugar", "Ficha recusada", "Já foi vendido", "Lead duplicado",
    "Localização não agradou", "Não consegui contatar", "Não possui renda", "Preço alto",
    "Produto não agradou", "Proposta do cliente com valor baixo", "Proposta inviável",
    "Tratada com qualificação", "Tratada sem qualificação", "Vendedor pesquisando produto"
  ].freeze

  def up
    tenant_ids = execute("SELECT id FROM tenants").map { |row| row["id"] }

    tenant_ids.each do |tenant_id|
      REASONS.each_with_index do |name, index|
        execute <<~SQL.squish
          INSERT INTO attribute_options (tenant_id, context, category, name, position, created_at, updated_at)
          VALUES (#{tenant_id}, 'lead', 'archive_reason', #{quote(name)}, #{index}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          ON CONFLICT (tenant_id, lower(name), category, context) DO NOTHING
        SQL
      end
    end
  end

  def down
    execute <<~SQL.squish
      DELETE FROM attribute_options
      WHERE context = 'lead'
        AND category = 'archive_reason'
        AND name IN (#{REASONS.map { |name| quote(name) }.join(", ")})
    SQL
  end
end

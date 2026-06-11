class SeedLeadStatusAttributeOptions < ActiveRecord::Migration[7.1]
  STATUSES = ["Novo", "Em Atendimento", "Aguardando Aceite", "Represado", "Descartado", "Concluido"].freeze
  STATUS_ALIASES = {
    "novo" => "Novo",
    "em_atendimento" => "Em Atendimento",
    "waiting_acceptance" => "Aguardando Aceite",
    "aguardando_aceite" => "Aguardando Aceite",
    "represado" => "Represado",
    "descartado" => "Descartado",
    "concluido" => "Concluido",
    "received" => "Novo"
  }.freeze

  def up
    STATUSES.each do |name|
      execute <<~SQL.squish
        INSERT INTO attribute_options (context, category, name, created_at, updated_at)
        VALUES ('lead', 'status', #{quote(name)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        ON CONFLICT (lower(name), category, context) DO NOTHING
      SQL
    end

    STATUS_ALIASES.each do |old_status, new_status|
      execute <<~SQL.squish
        UPDATE leads
        SET status = #{quote(new_status)}, updated_at = CURRENT_TIMESTAMP
        WHERE status = #{quote(old_status)}
      SQL
    end

    execute <<~SQL.squish
      UPDATE leads
      SET status = #{quote("Novo")}, updated_at = CURRENT_TIMESTAMP
      WHERE status IS NULL OR TRIM(status) = ''
    SQL
  end

  def down
    execute <<~SQL.squish
      DELETE FROM attribute_options
      WHERE context = 'lead'
        AND category = 'status'
        AND name IN (#{STATUSES.map { |status| quote(status) }.join(", ")})
    SQL
  end
end

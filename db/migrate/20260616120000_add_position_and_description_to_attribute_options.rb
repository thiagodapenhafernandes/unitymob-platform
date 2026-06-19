class AddPositionAndDescriptionToAttributeOptions < ActiveRecord::Migration[7.1]
  LEGACY_LEAD_STATUSES = ["Novo", "Em Atendimento", "Aguardando Aceite", "Represado", "Descartado", "Concluido"].freeze

  def up
    add_column :attribute_options, :position, :integer unless column_exists?(:attribute_options, :position)
    add_column :attribute_options, :description, :string unless column_exists?(:attribute_options, :description)

    unless index_exists?(:attribute_options, [:context, :category, :position], name: "index_attribute_options_on_context_category_position")
      add_index :attribute_options, [:context, :category, :position], name: "index_attribute_options_on_context_category_position"
    end

    backfill_positions
    seed_lead_statuses
  end

  def down
    if index_exists?(:attribute_options, [:context, :category, :position], name: "index_attribute_options_on_context_category_position")
      remove_index :attribute_options, name: "index_attribute_options_on_context_category_position"
    end
    remove_column :attribute_options, :position if column_exists?(:attribute_options, :position)
    remove_column :attribute_options, :description if column_exists?(:attribute_options, :description)
  end

  private

  # Define positions preservando a ordem visível atual:
  # - grupos genéricos: alfabético por nome;
  # - lead/status: legados na ordem fixa primeiro, depois customizados alfabéticos.
  def backfill_positions
    execute(<<~SQL)
      UPDATE attribute_options ao
      SET position = sub.rn - 1
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY context, category ORDER BY lower(name)) AS rn
        FROM attribute_options
      ) sub
      WHERE ao.id = sub.id AND ao.position IS NULL
    SQL

    rows = select_all("SELECT id, name FROM attribute_options WHERE context = 'lead' AND category = 'status'").to_a
    return if rows.empty?

    legacy = LEGACY_LEAD_STATUSES.filter_map { |name| rows.find { |row| row["name"] == name } }
    custom = (rows - legacy).sort_by { |row| row["name"].to_s.downcase }

    (legacy + custom).each_with_index do |row, index|
      execute("UPDATE attribute_options SET position = #{index} WHERE id = #{row['id'].to_i}")
    end
  end

  # Em bases sem catálogo de status, materializa os status legados para que o
  # board (kanban) e a tela de configuração tenham registros editáveis.
  def seed_lead_statuses
    count = select_value("SELECT COUNT(*) FROM attribute_options WHERE context = 'lead' AND category = 'status'").to_i
    return if count.positive?

    LEGACY_LEAD_STATUSES.each_with_index do |name, index|
      execute(<<~SQL)
        INSERT INTO attribute_options (name, category, context, position, created_at, updated_at)
        VALUES (#{quote(name)}, 'status', 'lead', #{index}, NOW(), NOW())
      SQL
    end
  end
end

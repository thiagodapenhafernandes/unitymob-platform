class HardenAttributeOptionsConstraints < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE attribute_options
      SET name = 'Sem nome'
      WHERE name IS NULL OR btrim(name) = '';
    SQL

    execute <<~SQL
      UPDATE attribute_options
      SET context = 'habitation'
      WHERE context IS NULL OR btrim(context) = '';
    SQL

    execute <<~SQL
      UPDATE attribute_options
      SET category = 'feature'
      WHERE category IS NULL OR btrim(category) = '';
    SQL

    # Remove duplicates while preserving the oldest ID for each logical key
    execute <<~SQL
      DELETE FROM attribute_options
      WHERE id IN (
        SELECT id FROM (
          SELECT id,
                 row_number() OVER (
                   PARTITION BY lower(name), category, context
                   ORDER BY id
                 ) AS row_number
          FROM attribute_options
        ) dedup
        WHERE dedup.row_number > 1
      );
    SQL

    change_column_null :attribute_options, :name, false
    change_column_null :attribute_options, :category, false
    change_column_null :attribute_options, :context, false

    add_index :attribute_options,
              "lower(name), category, context",
              unique: true,
              name: "index_attribute_options_on_context_category_lower_name"
  end

  def down
    remove_index :attribute_options, name: "index_attribute_options_on_context_category_lower_name"

    change_column_null :attribute_options, :name, true
    change_column_null :attribute_options, :category, true
    change_column_null :attribute_options, :context, true
  end
end

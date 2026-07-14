class AddDevelopmentResolutionToAiPropertySearch < ActiveRecord::Migration[7.1]
  def change
    change_table :property_settings, bulk: true do |t|
      t.boolean :ai_property_search_development_name_enabled, null: false, default: true
      t.boolean :ai_property_search_developer_name_enabled, null: false, default: true
      t.boolean :ai_property_search_fuzzy_matching_enabled, null: false, default: true
      t.decimal :ai_property_search_fuzzy_similarity_threshold, precision: 3, scale: 2, null: false, default: 0.30
      t.boolean :ai_property_search_development_aliases_enabled, null: false, default: true
      t.boolean :ai_property_search_search_by_characteristics_enabled, null: false, default: true
    end

    create_table :development_aliases do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :development, null: false, foreign_key: { to_table: :habitations }
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.timestamps
    end

    add_index :development_aliases, [:tenant_id, :normalized_name], name: "idx_development_aliases_tenant_name"
    add_index :development_aliases, [:tenant_id, :development_id, :normalized_name], unique: true, name: "idx_development_aliases_unique"
    add_index :development_aliases, :normalized_name, using: :gin, opclass: :gin_trgm_ops, name: "idx_development_aliases_name_trgm"
    add_index :habitations, "lower(nome_empreendimento) gin_trgm_ops", using: :gin, name: "idx_habitations_development_name_trgm"
    add_index :habitations, "lower(construtora) gin_trgm_ops", using: :gin, name: "idx_habitations_constructor_name_trgm"
  end
end

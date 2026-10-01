# Fase 1 do construtor de páginas (estrutura): a landing vira uma lista de blocos e ganha status
# Inativo/Rascunho/Publicado. Nada muda no site: `active` segue valendo (derivado do status) e
# `filter_params`/`content` continuam intactos até a limpeza final.
class AddStatusAndBlocksToLandingPages < ActiveRecord::Migration[7.1]
  def up
    add_column :landing_pages, :status, :string, default: "published", null: false
    execute "UPDATE landing_pages SET status = 'inactive' WHERE active IS NOT TRUE"
    add_index :landing_pages, [:tenant_id, :status]

    create_table :landing_page_blocks do |t|
      t.references :landing_page, null: false, foreign_key: true
      t.references :tenant, null: false, foreign_key: true
      t.string :block_type, null: false
      t.integer :position, null: false, default: 0
      t.boolean :visible, null: false, default: true
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :landing_page_blocks, [:landing_page_id, :position]
  end

  def down
    drop_table :landing_page_blocks
    remove_index :landing_pages, [:tenant_id, :status]
    remove_column :landing_pages, :status
  end
end

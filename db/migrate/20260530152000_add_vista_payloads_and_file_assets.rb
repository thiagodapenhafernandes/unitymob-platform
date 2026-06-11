class AddVistaPayloadsAndFileAssets < ActiveRecord::Migration[7.1]
  def change
    add_reference :habitations, :vista_import_batch, foreign_key: true
    add_column :habitations, :vista_payload, :jsonb, null: false, default: {}

    add_reference :proprietors, :vista_import_batch, foreign_key: true
    add_column :proprietors, :vista_payload, :jsonb, null: false, default: {}

    add_reference :admin_users, :vista_import_batch, foreign_key: true
    add_column :admin_users, :vista_payload, :jsonb, null: false, default: {}

    add_reference :leads, :vista_import_batch, foreign_key: true
    add_column :leads, :vista_payload, :jsonb, null: false, default: {}

    add_reference :habitation_broker_assignments, :vista_import_batch, foreign_key: true
    add_column :habitation_broker_assignments, :vista_payload, :jsonb, null: false, default: {}

    create_table :vista_file_assets do |t|
      t.references :vista_import_batch, null: false, foreign_key: true
      t.references :vista_raw_record, foreign_key: true
      t.references :habitation, foreign_key: true
      t.string :table_name, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.string :codigo_imovel
      t.string :codigo_cliente
      t.string :codigo_corretor
      t.string :source_path, null: false
      t.string :source_url
      t.string :filename, null: false
      t.string :active_storage_name
      t.bigint :active_storage_attachment_id
      t.integer :position
      t.integer :attempts, null: false, default: 0
      t.datetime :downloaded_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :habitations, :vista_payload, using: :gin
    add_index :proprietors, :vista_payload, using: :gin
    add_index :admin_users, :vista_payload, using: :gin
    add_index :leads, :vista_payload, using: :gin
    add_index :habitation_broker_assignments, :vista_payload, using: :gin, name: "idx_hba_on_vista_payload"

    add_index :vista_file_assets,
              [:vista_import_batch_id, :table_name, :source_path],
              unique: true,
              name: "idx_vista_file_assets_unique_source"
    add_index :vista_file_assets, [:status, :kind]
    add_index :vista_file_assets, [:codigo_imovel, :kind]
    add_index :vista_file_assets, :active_storage_attachment_id
    add_index :vista_file_assets, :metadata, using: :gin
  end
end

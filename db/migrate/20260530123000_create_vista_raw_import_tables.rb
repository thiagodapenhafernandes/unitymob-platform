class CreateVistaRawImportTables < ActiveRecord::Migration[7.1]
  def change
    create_table :vista_import_batches do |t|
      t.string :dump_dir, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :metadata, null: false, default: {}
      t.text :error_message

      t.timestamps
    end

    add_index :vista_import_batches, :status
    add_index :vista_import_batches, :dump_dir

    create_table :vista_raw_records do |t|
      t.references :vista_import_batch, null: false, foreign_key: true
      t.string :table_name, null: false
      t.integer :row_index, null: false
      t.string :source_key
      t.string :codigo_imovel
      t.string :codigo_cliente
      t.string :codigo_corretor
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end

    add_index :vista_raw_records,
              [:vista_import_batch_id, :table_name, :row_index],
              unique: true,
              name: "idx_vista_raw_records_batch_table_row"
    add_index :vista_raw_records, [:table_name, :codigo_imovel]
    add_index :vista_raw_records, [:table_name, :codigo_cliente]
    add_index :vista_raw_records, [:table_name, :codigo_corretor]
    add_index :vista_raw_records, [:table_name, :source_key]
    add_index :vista_raw_records, :payload, using: :gin
  end
end

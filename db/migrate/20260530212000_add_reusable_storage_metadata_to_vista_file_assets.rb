class AddReusableStorageMetadataToVistaFileAssets < ActiveRecord::Migration[7.1]
  def change
    change_table :vista_file_assets, bulk: true do |t|
      t.string :active_storage_key
      t.string :storage_checksum
      t.bigint :storage_byte_size
      t.string :storage_content_type
      t.string :storage_service_name
      t.datetime :reused_at
    end

    add_index :vista_file_assets, :active_storage_key
    add_index :vista_file_assets, [:vista_import_batch_id, :kind, :codigo_imovel, :filename], name: "idx_vista_file_assets_lookup_for_reuse"
  end
end

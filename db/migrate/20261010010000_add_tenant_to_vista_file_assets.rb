# frozen_string_literal: true

class AddTenantToVistaFileAssets < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_reference :vista_file_assets, :tenant, foreign_key: true, index: false
    add_index :vista_file_assets, :tenant_id, algorithm: :concurrently
    remove_index :vista_file_assets, name: "idx_vista_file_assets_unique_source", algorithm: :concurrently
    add_index :vista_file_assets, %i[tenant_id vista_import_batch_id table_name source_path],
      unique: true, name: "idx_vista_file_assets_tenant_unique_source", algorithm: :concurrently
  end

  def down
    remove_index :vista_file_assets, name: "idx_vista_file_assets_tenant_unique_source", algorithm: :concurrently
    add_index :vista_file_assets, %i[vista_import_batch_id table_name source_path],
      unique: true, name: "idx_vista_file_assets_unique_source", algorithm: :concurrently
    remove_index :vista_file_assets, :tenant_id, algorithm: :concurrently
    remove_reference :vista_file_assets, :tenant, foreign_key: true
  end
end

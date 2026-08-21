class CreateActiveStorageBlobAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :active_storage_blob_audit_logs do |t|
      t.bigint :tenant_id
      t.bigint :admin_user_id
      t.bigint :blob_id
      t.bigint :attachment_id
      t.string :record_type
      t.bigint :record_id
      t.string :attachment_name
      t.string :action, null: false
      t.string :source, null: false
      t.string :key
      t.string :filename
      t.string :content_type
      t.bigint :byte_size
      t.string :checksum
      t.string :service_name
      t.jsonb :metadata, default: {}, null: false
      t.inet :ip
      t.string :user_agent
      t.datetime :created_at, null: false
    end

    add_index :active_storage_blob_audit_logs, [:tenant_id, :created_at], name: "idx_as_blob_audit_tenant_created_at"
    add_index :active_storage_blob_audit_logs, :admin_user_id
    add_index :active_storage_blob_audit_logs, :blob_id
    add_index :active_storage_blob_audit_logs, :attachment_id
    add_index :active_storage_blob_audit_logs, [:record_type, :record_id], name: "idx_as_blob_audit_record"
    add_index :active_storage_blob_audit_logs, :action
    add_index :active_storage_blob_audit_logs, :source
    add_index :active_storage_blob_audit_logs, :key

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE OR REPLACE FUNCTION raise_active_storage_blob_audit_immutable() RETURNS trigger AS $$
          BEGIN
            RAISE EXCEPTION 'active_storage_blob_audit_logs is append-only';
          END; $$ LANGUAGE plpgsql;
        SQL
        execute <<~SQL
          CREATE TRIGGER active_storage_blob_audit_logs_no_update
            BEFORE UPDATE OR DELETE ON active_storage_blob_audit_logs
            FOR EACH ROW EXECUTE FUNCTION raise_active_storage_blob_audit_immutable();
        SQL
      end

      dir.down do
        execute "DROP TRIGGER IF EXISTS active_storage_blob_audit_logs_no_update ON active_storage_blob_audit_logs;"
        execute "DROP FUNCTION IF EXISTS raise_active_storage_blob_audit_immutable();"
      end
    end
  end
end

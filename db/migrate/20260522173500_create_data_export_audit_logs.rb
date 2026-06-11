class CreateDataExportAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :data_export_audit_logs do |t|
      t.references :admin_user, foreign_key: true
      t.string :export_type, null: false
      t.string :resource_name, null: false
      t.string :format, null: false
      t.integer :record_count, null: false, default: 0
      t.integer :selected_count, null: false, default: 0
      t.string :filename
      t.jsonb :filters, null: false, default: {}
      t.jsonb :fields, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.inet :ip
      t.string :user_agent
      t.datetime :created_at, null: false
    end

    add_index :data_export_audit_logs, :export_type
    add_index :data_export_audit_logs, :resource_name
    add_index :data_export_audit_logs, :format
    add_index :data_export_audit_logs, :created_at
    add_index :data_export_audit_logs, [:resource_name, :created_at]

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE OR REPLACE FUNCTION raise_data_export_audit_immutable()
          RETURNS trigger AS $$
          BEGIN
            RAISE EXCEPTION 'data_export_audit_logs is append-only';
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER data_export_audit_logs_no_update
            BEFORE UPDATE OR DELETE ON data_export_audit_logs
            FOR EACH ROW EXECUTE FUNCTION raise_data_export_audit_immutable();
        SQL
      end

      dir.down do
        execute "DROP TRIGGER IF EXISTS data_export_audit_logs_no_update ON data_export_audit_logs;"
        execute "DROP FUNCTION IF EXISTS raise_data_export_audit_immutable();"
      end
    end
  end
end

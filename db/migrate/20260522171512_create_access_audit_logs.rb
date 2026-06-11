class CreateAccessAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :access_audit_logs do |t|
      t.bigint :admin_user_id
      t.string :event_type, null: false
      t.string :result, null: false
      t.string :reason
      t.string :email
      t.inet :ip
      t.string :user_agent
      t.string :device_type
      t.string :browser
      t.string :platform
      t.string :path
      t.string :request_method
      t.string :controller_name
      t.string :action_name
      t.jsonb :metadata, default: {}, null: false
      t.datetime :created_at, null: false
    end

    add_index :access_audit_logs, :admin_user_id
    add_index :access_audit_logs, [:admin_user_id, :created_at]
    add_index :access_audit_logs, :event_type
    add_index :access_audit_logs, :result
    add_index :access_audit_logs, :ip
    add_index :access_audit_logs, :created_at

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE OR REPLACE FUNCTION raise_access_audit_immutable() RETURNS trigger AS $$
          BEGIN
            RAISE EXCEPTION 'access_audit_logs is append-only';
          END; $$ LANGUAGE plpgsql;
        SQL
        execute <<~SQL
          CREATE TRIGGER access_audit_logs_no_update
            BEFORE UPDATE OR DELETE ON access_audit_logs
            FOR EACH ROW EXECUTE FUNCTION raise_access_audit_immutable();
        SQL
      end
      dir.down do
        execute "DROP TRIGGER IF EXISTS access_audit_logs_no_update ON access_audit_logs;"
        execute "DROP FUNCTION IF EXISTS raise_access_audit_immutable();"
      end
    end
  end
end

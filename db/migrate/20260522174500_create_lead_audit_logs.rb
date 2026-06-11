class CreateLeadAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_audit_logs do |t|
      t.bigint :lead_id, null: false
      t.bigint :admin_user_id
      t.string :action, null: false
      t.string :source, null: false
      t.text :changed_fields, array: true, default: [], null: false
      t.jsonb :changeset, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false
      t.inet :ip
      t.string :user_agent
      t.datetime :created_at, null: false
    end

    add_index :lead_audit_logs, :lead_id
    add_index :lead_audit_logs, :admin_user_id
    add_index :lead_audit_logs, [:lead_id, :created_at]
    add_index :lead_audit_logs, [:admin_user_id, :created_at]
    add_index :lead_audit_logs, :action
    add_index :lead_audit_logs, :source
    add_index :lead_audit_logs, :changed_fields, using: :gin

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE OR REPLACE FUNCTION raise_lead_audit_immutable()
          RETURNS trigger AS $$
          BEGIN
            RAISE EXCEPTION 'lead_audit_logs is append-only';
          END;
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER lead_audit_logs_no_update
            BEFORE UPDATE OR DELETE ON lead_audit_logs
            FOR EACH ROW EXECUTE FUNCTION raise_lead_audit_immutable();
        SQL
      end

      dir.down do
        execute "DROP TRIGGER IF EXISTS lead_audit_logs_no_update ON lead_audit_logs;"
        execute "DROP FUNCTION IF EXISTS raise_lead_audit_immutable();"
      end
    end
  end
end

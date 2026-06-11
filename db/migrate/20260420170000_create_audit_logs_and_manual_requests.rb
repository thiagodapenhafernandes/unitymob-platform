class CreateAuditLogsAndManualRequests < ActiveRecord::Migration[7.1]
  # Fase 6 — Antifraude + auditoria append-only + check-in manual.
  def change
    # Trilha de auditoria IMUTÁVEL (trigger PG impede UPDATE/DELETE).
    create_table :checkin_audit_logs do |t|
      t.references :check_in, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.references :actor_admin_user, foreign_key: { to_table: :admin_users }
      t.string :action, null: false   # created, closed, manual_request, forced, flagged_suspicious
      t.jsonb :metadata, default: {}, null: false
      t.inet :ip
      t.datetime :created_at, null: false
    end
    add_index :checkin_audit_logs, [:admin_user_id, :created_at]
    add_index :checkin_audit_logs, :action

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE OR REPLACE FUNCTION raise_checkin_audit_immutable() RETURNS trigger AS $$
          BEGIN
            RAISE EXCEPTION 'checkin_audit_logs is append-only';
          END; $$ LANGUAGE plpgsql;
        SQL
        execute <<~SQL
          CREATE TRIGGER checkin_audit_logs_no_update
            BEFORE UPDATE OR DELETE ON checkin_audit_logs
            FOR EACH ROW EXECUTE FUNCTION raise_checkin_audit_immutable();
        SQL
      end
      dir.down do
        execute "DROP TRIGGER IF EXISTS checkin_audit_logs_no_update ON checkin_audit_logs;"
        execute "DROP FUNCTION IF EXISTS raise_checkin_audit_immutable();"
      end
    end

    # Solicitação manual — quando GPS falha, corretor pede review do admin.
    create_table :manual_checkin_requests do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.text :justification, null: false
      t.integer :status, default: 0, null: false  # pending/approved/rejected
      t.references :reviewed_by_admin_user, foreign_key: { to_table: :admin_users }
      t.datetime :reviewed_at
      t.text :review_notes
      t.references :approved_check_in, foreign_key: { to_table: :check_ins }
      t.timestamps
    end
    add_index :manual_checkin_requests, :status

    # Campos de suspeita direto no check_in (desnormalizado para filtros rápidos).
    add_column :check_ins, :suspicious, :boolean, default: false, null: false
    add_column :check_ins, :suspicious_reasons, :jsonb, default: []
    add_column :check_ins, :fingerprint_hash, :string
    add_index :check_ins, :fingerprint_hash
    add_index :check_ins, :suspicious
  end
end

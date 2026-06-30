class AllowPlatformAccessAuditLogs < ActiveRecord::Migration[7.1]
  def up
    change_column_null :access_audit_logs, :tenant_id, true

    execute <<~SQL
      CREATE OR REPLACE FUNCTION enforce_access_audit_log_tenant_governance()
      RETURNS trigger AS $$
      DECLARE
        owner_is_system_admin boolean;
        owner_tenant_id bigint;
      BEGIN
        IF NEW.admin_user_id IS NULL THEN
          RETURN NEW;
        END IF;

        SELECT super_admin, tenant_id
          INTO owner_is_system_admin, owner_tenant_id
        FROM admin_users
        WHERE id = NEW.admin_user_id;

        IF owner_is_system_admin IS DISTINCT FROM TRUE AND NEW.tenant_id IS NULL THEN
          RAISE EXCEPTION 'access audit log tenant is required for account users'
            USING ERRCODE = '23514';
        END IF;

        IF owner_is_system_admin = TRUE AND NEW.tenant_id IS NOT NULL THEN
          RAISE EXCEPTION 'platform access audit log must not belong to a tenant'
            USING ERRCODE = '23514';
        END IF;

        IF owner_is_system_admin IS DISTINCT FROM TRUE AND owner_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
          RAISE EXCEPTION 'access audit log tenant must match admin user tenant'
            USING ERRCODE = '23514';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS trigger_enforce_access_audit_log_tenant_governance ON access_audit_logs;
      CREATE TRIGGER trigger_enforce_access_audit_log_tenant_governance
      BEFORE INSERT OR UPDATE OF tenant_id, admin_user_id
      ON access_audit_logs
      FOR EACH ROW
      EXECUTE FUNCTION enforce_access_audit_log_tenant_governance();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS trigger_enforce_access_audit_log_tenant_governance ON access_audit_logs;
      DROP FUNCTION IF EXISTS enforce_access_audit_log_tenant_governance();
    SQL

    default_tenant_id = select_value("SELECT id FROM tenants ORDER BY id ASC LIMIT 1")
    raise ActiveRecord::IrreversibleMigration, "Cannot restore NOT NULL access_audit_logs.tenant_id without a tenant" if default_tenant_id.blank?

    execute "ALTER TABLE access_audit_logs DISABLE TRIGGER USER"
    begin
      execute <<~SQL.squish
        UPDATE access_audit_logs
        SET tenant_id = #{default_tenant_id.to_i}
        WHERE tenant_id IS NULL
      SQL
    ensure
      execute "ALTER TABLE access_audit_logs ENABLE TRIGGER USER"
    end

    change_column_null :access_audit_logs, :tenant_id, false
  end
end

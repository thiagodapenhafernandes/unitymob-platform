class AllowPlatformTrustedDevices < ActiveRecord::Migration[7.1]
  def up
    change_column_null :trusted_devices, :tenant_id, true

    execute <<~SQL
      CREATE OR REPLACE FUNCTION enforce_trusted_device_tenant_governance()
      RETURNS trigger AS $$
      DECLARE
        owner_is_system_admin boolean;
        owner_tenant_id bigint;
      BEGIN
        SELECT super_admin, tenant_id
          INTO owner_is_system_admin, owner_tenant_id
        FROM admin_users
        WHERE id = NEW.admin_user_id;

        IF owner_is_system_admin IS DISTINCT FROM TRUE AND NEW.tenant_id IS NULL THEN
          RAISE EXCEPTION 'trusted device tenant is required for account users'
            USING ERRCODE = '23514';
        END IF;

        IF owner_is_system_admin = TRUE AND NEW.tenant_id IS NOT NULL THEN
          RAISE EXCEPTION 'platform trusted device must not belong to a tenant'
            USING ERRCODE = '23514';
        END IF;

        IF owner_is_system_admin IS DISTINCT FROM TRUE AND owner_tenant_id IS DISTINCT FROM NEW.tenant_id THEN
          RAISE EXCEPTION 'trusted device tenant must match admin user tenant'
            USING ERRCODE = '23514';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS trigger_enforce_trusted_device_tenant_governance ON trusted_devices;
      CREATE TRIGGER trigger_enforce_trusted_device_tenant_governance
      BEFORE INSERT OR UPDATE OF tenant_id, admin_user_id
      ON trusted_devices
      FOR EACH ROW
      EXECUTE FUNCTION enforce_trusted_device_tenant_governance();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS trigger_enforce_trusted_device_tenant_governance ON trusted_devices;
      DROP FUNCTION IF EXISTS enforce_trusted_device_tenant_governance();
    SQL

    default_tenant_id = select_value("SELECT id FROM tenants ORDER BY id ASC LIMIT 1")
    if default_tenant_id.present?
      execute <<~SQL.squish
        UPDATE trusted_devices
        SET tenant_id = #{default_tenant_id.to_i},
            updated_at = CURRENT_TIMESTAMP
        WHERE tenant_id IS NULL
      SQL
    end

    change_column_null :trusted_devices, :tenant_id, false
  end
end

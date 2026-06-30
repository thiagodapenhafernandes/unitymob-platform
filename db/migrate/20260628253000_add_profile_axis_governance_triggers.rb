class AddProfileAxisGovernanceTriggers < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION enforce_profile_axis_governance()
      RETURNS trigger AS $$
      BEGIN
        IF NEW.axis = 'horizontal' THEN
          IF NOT EXISTS (
            SELECT 1
            FROM profiles parent
            WHERE parent.id = NEW.vertical_profile_id
              AND parent.tenant_id = NEW.tenant_id
              AND parent.axis = 'vertical'
          ) THEN
            RAISE EXCEPTION 'horizontal profile must reference a vertical profile from the same tenant'
              USING ERRCODE = '23514';
          END IF;
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS trigger_enforce_profile_axis_governance ON profiles;
      CREATE TRIGGER trigger_enforce_profile_axis_governance
      BEFORE INSERT OR UPDATE OF tenant_id, axis, vertical_profile_id
      ON profiles
      FOR EACH ROW
      EXECUTE FUNCTION enforce_profile_axis_governance();
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION enforce_admin_user_profile_governance()
      RETURNS trigger AS $$
      DECLARE
        user_profile_axis text;
        user_profile_position integer;
        horizontal_axis text;
        horizontal_vertical_profile_id bigint;
        manager_profile_position integer;
        cycle_found boolean;
      BEGIN
        IF NEW.profile_id IS NOT NULL THEN
          SELECT axis, position
            INTO user_profile_axis, user_profile_position
          FROM profiles
          WHERE id = NEW.profile_id
            AND tenant_id = NEW.tenant_id;

          IF user_profile_axis IS DISTINCT FROM 'vertical' THEN
            RAISE EXCEPTION 'admin user profile must be a vertical profile from the same tenant'
              USING ERRCODE = '23514';
          END IF;
        END IF;

        IF NEW.horizontal_profile_id IS NOT NULL THEN
          IF NEW.profile_id IS NULL THEN
            RAISE EXCEPTION 'admin user horizontal profile requires a vertical profile'
              USING ERRCODE = '23514';
          END IF;

          SELECT axis, vertical_profile_id
            INTO horizontal_axis, horizontal_vertical_profile_id
          FROM profiles
          WHERE id = NEW.horizontal_profile_id
            AND tenant_id = NEW.tenant_id;

          IF horizontal_axis IS DISTINCT FROM 'horizontal' THEN
            RAISE EXCEPTION 'admin user horizontal profile must be a horizontal profile from the same tenant'
              USING ERRCODE = '23514';
          END IF;

          IF horizontal_vertical_profile_id IS DISTINCT FROM NEW.profile_id THEN
            RAISE EXCEPTION 'admin user horizontal profile must be attached to the user vertical profile'
              USING ERRCODE = '23514';
          END IF;
        END IF;

        IF NEW.manager_id IS NOT NULL THEN
          IF NEW.profile_id IS NULL THEN
            RAISE EXCEPTION 'admin user with manager requires a vertical profile'
              USING ERRCODE = '23514';
          END IF;

          SELECT manager_profile.position
            INTO manager_profile_position
          FROM admin_users manager
          JOIN profiles manager_profile
            ON manager_profile.id = manager.profile_id
           AND manager_profile.tenant_id = manager.tenant_id
          WHERE manager.id = NEW.manager_id
            AND manager.tenant_id = NEW.tenant_id
            AND manager_profile.axis = 'vertical';

          IF manager_profile_position IS NULL OR manager_profile_position >= user_profile_position THEN
            RAISE EXCEPTION 'admin user manager must be above the user vertical profile'
              USING ERRCODE = '23514';
          END IF;

          IF NEW.id IS NOT NULL THEN
            WITH RECURSIVE subtree AS (
              SELECT id
              FROM admin_users
              WHERE manager_id = NEW.id
                AND tenant_id = NEW.tenant_id
              UNION ALL
              SELECT child.id
              FROM admin_users child
              JOIN subtree parent ON child.manager_id = parent.id
              WHERE child.tenant_id = NEW.tenant_id
            )
            SELECT EXISTS(SELECT 1 FROM subtree WHERE id = NEW.manager_id)
              INTO cycle_found;

            IF cycle_found THEN
              RAISE EXCEPTION 'admin user manager cannot create a hierarchy cycle'
                USING ERRCODE = '23514';
            END IF;
          END IF;
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS trigger_enforce_admin_user_profile_governance ON admin_users;
      CREATE TRIGGER trigger_enforce_admin_user_profile_governance
      BEFORE INSERT OR UPDATE OF tenant_id, profile_id, horizontal_profile_id, manager_id
      ON admin_users
      FOR EACH ROW
      EXECUTE FUNCTION enforce_admin_user_profile_governance();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS trigger_enforce_admin_user_profile_governance ON admin_users;
      DROP FUNCTION IF EXISTS enforce_admin_user_profile_governance();
      DROP TRIGGER IF EXISTS trigger_enforce_profile_axis_governance ON profiles;
      DROP FUNCTION IF EXISTS enforce_profile_axis_governance();
    SQL
  end
end

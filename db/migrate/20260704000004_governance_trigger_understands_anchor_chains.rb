class GovernanceTriggerUnderstandsAnchorChains < ActiveRecord::Migration[7.1]
  # Âncoras de perfis horizontais podem ser ENCADEADAS (função → função → perfil
  # vertical). O app já resolve pela raiz (Profile#root_vertical_profile); o
  # trigger de governança comparava a âncora DIRETA com o vertical do usuário e
  # barrava cadeias legítimas. Agora ele sobe a cadeia e compara a RAIZ.
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION public.enforce_admin_user_profile_governance() RETURNS trigger
          LANGUAGE plpgsql
          AS $$
      DECLARE
        user_profile_axis text;
        user_profile_position integer;
        horizontal_axis text;
        horizontal_root_vertical_id bigint;
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

          SELECT axis
            INTO horizontal_axis
          FROM profiles
          WHERE id = NEW.horizontal_profile_id
            AND tenant_id = NEW.tenant_id;

          IF horizontal_axis IS DISTINCT FROM 'horizontal' THEN
            RAISE EXCEPTION 'admin user horizontal profile must be a horizontal profile from the same tenant'
              USING ERRCODE = '23514';
          END IF;

          -- Sobe a cadeia de âncoras (função → função → ... → vertical) e
          -- compara a RAIZ vertical com o perfil do usuário.
          WITH RECURSIVE anchor_chain AS (
            SELECT p.id, p.axis, p.vertical_profile_id, 0 AS depth
            FROM profiles p
            WHERE p.id = NEW.horizontal_profile_id
              AND p.tenant_id = NEW.tenant_id
            UNION ALL
            SELECT parent.id, parent.axis, parent.vertical_profile_id, chain.depth + 1
            FROM profiles parent
            JOIN anchor_chain chain ON parent.id = chain.vertical_profile_id
            WHERE chain.axis = 'horizontal'
              AND chain.depth < 6
              AND parent.tenant_id = NEW.tenant_id
          )
          SELECT id
            INTO horizontal_root_vertical_id
          FROM anchor_chain
          WHERE axis = 'vertical'
          LIMIT 1;

          IF horizontal_root_vertical_id IS DISTINCT FROM NEW.profile_id THEN
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
      $$;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "restaure a versão anterior da função a partir do structure.sql do commit anterior"
  end
end

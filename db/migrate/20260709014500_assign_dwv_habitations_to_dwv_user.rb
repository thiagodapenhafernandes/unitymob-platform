class AssignDwvHabitationsToDwvUser < ActiveRecord::Migration[7.1]
  DWV_USER_EMAIL = "laudicardoso@gmail.com".freeze

  def up
    say_with_time "Assigning DWV habitations to the DWV user" do
      rows = select_all(<<~SQL.squish)
        SELECT id, tenant_id
        FROM admin_users
        WHERE tenant_id IS NOT NULL
          AND super_admin = FALSE
          AND LOWER(email) = #{connection.quote(DWV_USER_EMAIL)}
      SQL

      rows.sum do |row|
        update(<<~SQL.squish)
          UPDATE habitations
          SET admin_user_id = #{connection.quote(row["id"])}
          WHERE tenant_id = #{connection.quote(row["tenant_id"])}
            AND COALESCE(imovel_dwv, '') = 'Sim'
            AND admin_user_id IS NULL
        SQL
      end
    end
  end

  def down
    # Data backfill only. Existing ownership should not be removed automatically.
  end
end

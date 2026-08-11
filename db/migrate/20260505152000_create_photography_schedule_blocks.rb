class CreatePhotographyScheduleBlocks < ActiveRecord::Migration[7.1]
  def up
    create_table :photography_schedule_blocks do |t|
      t.date :date, null: false
      t.string :reason
      t.references :created_by, foreign_key: { to_table: :admin_users }

      t.timestamps
    end

    add_index :photography_schedule_blocks, :date, unique: true

    photographer_permissions = {
      "admin" => false,
      "dashboard" => { "view" => false },
      "agenda_fotografia" => { "view" => true, "manage" => false }
    }

    permissions_json = connection.quote(photographer_permissions.to_json)

    execute(<<~SQL)
      UPDATE profiles
      SET active = TRUE,
          permissions = #{permissions_json}::jsonb,
          updated_at = CURRENT_TIMESTAMP
      WHERE name = 'Fotógrafo'
    SQL

    execute(<<~SQL)
      INSERT INTO profiles (name, active, permissions, created_at, updated_at)
      SELECT 'Fotógrafo', TRUE, #{permissions_json}::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      WHERE NOT EXISTS (
        SELECT 1 FROM profiles WHERE name = 'Fotógrafo'
      )
    SQL
  end

  def down
    drop_table :photography_schedule_blocks
  end
end

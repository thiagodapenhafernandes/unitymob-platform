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

    Profile.find_or_create_by!(name: "Fotógrafo") do |profile|
      profile.active = true
      profile.permissions = photographer_permissions
    end
  end

  def down
    drop_table :photography_schedule_blocks
  end
end

class CreateTrustedDevices < ActiveRecord::Migration[7.1]
  def change
    create_table :trusted_devices do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :admin_users }
      t.string :name
      t.string :fingerprint, null: false
      t.string :status, null: false, default: "pending"
      t.string :device_type
      t.string :browser
      t.string :platform
      t.inet :last_ip
      t.string :user_agent
      t.datetime :trusted_at
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :trusted_devices, [:admin_user_id, :fingerprint], unique: true
    add_index :trusted_devices, :status
    add_index :trusted_devices, :last_ip
  end
end

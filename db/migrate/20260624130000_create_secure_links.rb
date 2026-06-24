class CreateSecureLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :secure_links do |t|
      t.references :lead, null: false, foreign_key: true
      t.string   :token, null: false
      t.integer  :action_type, null: false, default: 0 # 0 phone, 1 email, 2 view
      t.datetime :expires_at
      t.boolean  :active, null: false, default: true
      t.integer  :access_count, null: false, default: 0
      t.datetime :first_accessed_at
      t.datetime :last_accessed_at
      t.bigint   :issued_to_admin_user_id

      t.timestamps
    end

    add_index :secure_links, :token, unique: true
    add_index :secure_links, [:lead_id, :action_type]
  end
end

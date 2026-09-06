class CreateBrowserExtensionGrants < ActiveRecord::Migration[7.1]
  def change
    create_table :browser_extension_grants do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.references :trusted_device, foreign_key: true
      t.string :extension_id, null: false
      t.string :challenge_digest, null: false
      t.datetime :challenge_expires_at, null: false
      t.datetime :exchanged_at
      t.string :token_digest
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :browser_extension_grants, :challenge_digest, unique: true
    add_index :browser_extension_grants, :token_digest, unique: true
    add_index :browser_extension_grants, :expires_at
  end
end

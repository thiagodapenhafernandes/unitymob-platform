class CreateAdminLoginChallenges < ActiveRecord::Migration[7.1]
  def change
    create_table :admin_login_challenges do |t|
      t.string :token_digest, null: false
      t.string :code_digest, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :admin_login_challenges, :token_digest, unique: true
    add_index :admin_login_challenges, :expires_at
  end
end

class CreateDiscoveryV2 < ActiveRecord::Migration[7.1]
  def change
    create_table :account_memberships do |t|
      t.string :instance_id, null: false
      t.string :tenant_id, null: false
      t.string :user_id, null: false
      t.string :email, null: false
      t.string :tenant_name, null: false
      t.boolean :active, null: false, default: false
      t.datetime :source_updated_at, null: false
      t.timestamps
    end
    add_index :account_memberships, [:instance_id, :tenant_id, :user_id], unique: true, name: 'index_memberships_identity'
    add_index :account_memberships, [:email, :active]
    create_table :discovery_challenges do |t|
      t.string :token_digest, null: false
      t.string :email, null: false
      t.string :code_digest, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
    end
    add_index :discovery_challenges, :token_digest, unique: true
    add_index :discovery_challenges, :expires_at
    create_table :discovery_limits do |t|
      t.string :key, null: false
      t.integer :hits, null: false, default: 0
      t.datetime :expires_at, null: false
    end
    add_index :discovery_limits, :key, unique: true
    add_index :discovery_limits, :expires_at
  end
end

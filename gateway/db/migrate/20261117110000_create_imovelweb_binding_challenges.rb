class CreateImovelwebBindingChallenges < ActiveRecord::Migration[7.1]
  def change
    create_table :imovelweb_binding_challenges do |t|
      t.string :token_digest, null: false
      t.string :code_digest, null: false
      t.string :client_key, null: false
      t.string :client_code, null: false
      t.string :environment, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :verified_at
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :imovelweb_binding_challenges, :token_digest, unique: true
    add_index :imovelweb_binding_challenges, :expires_at
  end
end

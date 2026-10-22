class CreateMetaOauthAttempts < ActiveRecord::Migration[7.1]
  def change
    create_table :meta_oauth_attempts do |t|
      t.string :instance_id, null: false
      t.string :tenant_id, null: false
      t.string :user_id, null: false
      t.string :nonce_digest, null: false
      t.string :start_digest, null: false
      t.string :state_digest
      t.string :browser_digest
      t.string :handoff_digest
      t.text :encrypted_result
      t.string :failure
      t.datetime :started_at
      t.datetime :callback_at
      t.datetime :consumed_at
      t.datetime :expires_at, null: false
    end
    %i[start_digest state_digest handoff_digest].each { |column| add_index :meta_oauth_attempts, column, unique: true }
    add_index :meta_oauth_attempts, :expires_at
  end
end

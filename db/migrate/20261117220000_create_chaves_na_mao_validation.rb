class CreateChavesNaMaoValidation < ActiveRecord::Migration[7.1]
  def change
    create_table :chaves_na_mao_connections do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.string :route_key, null: false
      t.string :account_code, null: false
      t.text :integration_token
      t.boolean :enabled, null: false, default: false
      t.timestamps
    end
    add_index :chaves_na_mao_connections, :route_key, unique: true

    create_table :chaves_na_mao_lead_receipts do |t|
      t.references :chaves_na_mao_connection, null: false, foreign_key: true, index: false
      t.string :payload_digest, null: false
      t.text :payload, null: false
      t.datetime :received_at, null: false
      t.timestamps
    end
    add_index :chaves_na_mao_lead_receipts, [:chaves_na_mao_connection_id, :payload_digest],
      unique: true, name: "idx_chaves_receipts_connection_digest"
  end
end

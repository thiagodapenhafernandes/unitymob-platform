class CreatePropertyIntakeReceipts < ActiveRecord::Migration[7.1]
  def change
    add_column :tenants, :property_intake_token_digest, :string
    add_index :tenants, :property_intake_token_digest, unique: true

    create_table :property_intake_receipts do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :habitation, foreign_key: { on_delete: :nullify }
      t.string :external_id, null: false
      t.string :payload_digest, null: false
      t.string :captador_external_id, null: false
      t.string :captador_nome, null: false
      t.datetime :captured_at, null: false
      t.timestamps
      t.index [:tenant_id, :external_id], unique: true
    end
  end
end

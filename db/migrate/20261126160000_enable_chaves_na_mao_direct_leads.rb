class EnableChavesNaMaoDirectLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :chaves_na_mao_connections, :login_email, :string
    add_column :chaves_na_mao_connections, :operational, :boolean, null: false, default: false
    add_column :chaves_na_mao_connections, :last_lead_received_at, :datetime
    add_column :chaves_na_mao_lead_receipts, :event_id, :string
    add_column :chaves_na_mao_lead_receipts, :status, :string, null: false, default: "captured"
    add_column :chaves_na_mao_lead_receipts, :reason, :string
    add_column :chaves_na_mao_lead_receipts, :processed_at, :datetime
    add_reference :chaves_na_mao_lead_receipts, :lead, foreign_key: true
    add_index :chaves_na_mao_lead_receipts, [:chaves_na_mao_connection_id, :event_id],
      unique: true, name: "idx_chaves_receipts_connection_event"
  end
end

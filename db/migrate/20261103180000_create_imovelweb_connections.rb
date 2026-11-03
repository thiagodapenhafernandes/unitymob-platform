class CreateImovelwebConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :imovelweb_connections do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :route_key, null: false
      t.string :client_code, null: false
      t.string :environment, null: false, default: "sandbox"
      t.boolean :enabled, null: false, default: false
      t.datetime :authorized_at
      t.datetime :last_lead_received_at
      t.timestamps
    end
    add_index :imovelweb_connections, :route_key, unique: true
    add_index :imovelweb_connections, [:environment, :client_code], unique: true
    add_check_constraint :imovelweb_connections, "environment IN ('sandbox', 'production')", name: "imovelweb_environment"

    create_table :imovelweb_listings do |t|
      t.references :imovelweb_connection, null: false, foreign_key: true
      t.references :habitation, null: false, foreign_key: true
      t.string :reference, null: false
      t.string :external_id
      t.timestamps
    end
    add_index :imovelweb_listings, [:imovelweb_connection_id, :reference], unique: true, name: "index_imovelweb_listing_reference"
    add_index :imovelweb_listings, [:imovelweb_connection_id, :external_id], unique: true, where: "external_id IS NOT NULL", name: "index_imovelweb_listing_external"

    create_table :imovelweb_lead_receipts do |t|
      t.references :imovelweb_connection, null: false, foreign_key: true
      t.references :lead, foreign_key: { on_delete: :nullify }
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.text :payload, null: false
      t.string :status, null: false, default: "pending"
      t.string :reason
      t.datetime :received_at, null: false
      t.datetime :processed_at
      t.timestamps
    end
    add_index :imovelweb_lead_receipts, [:imovelweb_connection_id, :event_id], unique: true, name: "index_imovelweb_receipt_identity"
    add_index :imovelweb_lead_receipts, [:status, :received_at]
    add_check_constraint :imovelweb_lead_receipts, "status IN ('pending', 'processed', 'quarantined')", name: "imovelweb_receipt_status"
  end
end

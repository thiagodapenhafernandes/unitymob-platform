class CreateSupportDesk < ActiveRecord::Migration[7.1]
  def change
    create_table :support_accounts do |t|
      t.string :uid, null: false
      t.string :name, null: false
      t.bigint :local_tenant_id
      t.string :endpoint, null: false
      t.text :secret, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :support_accounts, :uid, unique: true
    add_index :support_accounts, :local_tenant_id, unique: true
    create_table :support_tickets do |t|
      t.references :account, null: false, foreign_key: { to_table: :support_accounts }
      t.string :uid, null: false
      t.string :requester_id, null: false
      t.string :requester_name, null: false
      t.string :subject, null: false
      t.jsonb :intake, null: false, default: {}
      t.string :source_path
      t.string :status, null: false, default: "aberto"
      t.string :priority, null: false, default: "normal"
      t.bigint :assignee_id
      t.string :assignee_name
      t.string :labels, null: false, default: ""
      t.string :previous_uid
      t.integer :revision, null: false, default: 0
      t.datetime :first_response_at
      t.datetime :resolved_at
      t.datetime :read_at
      t.timestamps
    end
    add_index :support_tickets, :uid, unique: true
    add_index :support_tickets, [:account_id, :requester_id, :updated_at]
    add_index :support_tickets, [:status, :updated_at]
    add_index :support_tickets, :assignee_id
    create_table :support_messages do |t|
      t.references :ticket, null: false, foreign_key: { to_table: :support_tickets }
      t.string :uid, null: false
      t.string :side, null: false
      t.string :author, null: false
      t.text :body, null: false, default: ""
      t.boolean :internal, null: false, default: false
      t.timestamps
    end
    add_index :support_messages, :uid, unique: true
    create_table :support_deliveries do |t|
      t.references :account, null: false, foreign_key: { to_table: :support_accounts }
      t.references :ticket, foreign_key: { to_table: :support_tickets }
      t.string :uid, null: false
      t.jsonb :payload, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :delivered_at
      t.datetime :next_attempt_at, null: false
      t.string :last_error
      t.timestamps
    end
    add_index :support_deliveries, :uid, unique: true
    add_index :support_deliveries, [:delivered_at, :next_attempt_at]
    create_table :support_receipts do |t|
      t.references :account, null: false, foreign_key: { to_table: :support_accounts }
      t.string :uid, null: false
      t.timestamps
    end
    add_index :support_receipts, [:account_id, :uid], unique: true
    create_table :support_access_sessions do |t|
      t.references :account, null: false, foreign_key: { to_table: :support_accounts }
      t.references :ticket, null: false, foreign_key: { to_table: :support_tickets }
      t.string :token_digest, null: false
      t.string :operator_id, null: false
      t.string :operator_name, null: false
      t.string :requester_id, null: false
      t.datetime :redeem_before, null: false
      t.datetime :started_at
      t.datetime :expires_at
      t.datetime :ended_at
      t.timestamps
    end
    add_index :support_access_sessions, :token_digest, unique: true
    create_table :support_audits do |t|
      t.references :account, null: false, foreign_key: { to_table: :support_accounts }
      t.references :ticket, foreign_key: { to_table: :support_tickets }
      t.string :actor, null: false
      t.string :action, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
  end
end

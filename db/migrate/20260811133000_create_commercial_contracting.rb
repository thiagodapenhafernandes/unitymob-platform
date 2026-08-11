class CreateCommercialContracting < ActiveRecord::Migration[7.1]
  def change
    create_table :commercial_contract_terms_versions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :version, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :document_hash
      t.datetime :published_at
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :commercial_contract_terms_versions, [:tenant_id, :version], unique: true, name: "idx_contract_terms_tenant_version"
    add_index :commercial_contract_terms_versions, [:tenant_id, :active], name: "idx_contract_terms_tenant_active"

    create_table :commercial_contract_proposals do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.references :terms_version, null: false, foreign_key: { to_table: :commercial_contract_terms_versions }
      t.string :public_token, null: false
      t.string :status, null: false, default: "draft"
      t.string :title, null: false
      t.string :legal_business_name, null: false
      t.string :trade_name
      t.string :cnpj, null: false
      t.string :client_email
      t.string :client_phone
      t.string :plan_name, null: false, default: "Unitymob completo"
      t.integer :monthly_fee_cents, null: false, default: 300_000
      t.integer :setup_fee_cents, null: false, default: 0
      t.integer :minimum_term_months, null: false, default: 0
      t.date :starts_on
      t.datetime :expires_at
      t.text :scope_summary
      t.text :billing_notes
      t.text :external_costs_note
      t.datetime :sent_at
      t.datetime :viewed_at
      t.datetime :accepted_at
      t.datetime :canceled_at
      t.string :representative_name
      t.string :representative_cpf
      t.string :representative_role
      t.string :representative_email
      t.string :representative_phone
      t.string :otp_digest
      t.datetime :otp_sent_at
      t.datetime :otp_expires_at
      t.integer :otp_attempts, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :commercial_contract_proposals, :public_token, unique: true
    add_index :commercial_contract_proposals, [:tenant_id, :status], name: "idx_contract_proposals_tenant_status"
    add_index :commercial_contract_proposals, [:tenant_id, :created_at], name: "idx_contract_proposals_tenant_created"

    create_table :commercial_contract_acceptances do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :proposal, null: false, foreign_key: { to_table: :commercial_contract_proposals }
      t.references :terms_version, null: false, foreign_key: { to_table: :commercial_contract_terms_versions }
      t.string :acceptance_token, null: false
      t.string :legal_business_name, null: false
      t.string :cnpj, null: false
      t.string :representative_name, null: false
      t.string :representative_cpf, null: false
      t.string :representative_role, null: false
      t.string :representative_email, null: false
      t.string :representative_phone
      t.string :ip_address
      t.text :user_agent
      t.string :terms_hash, null: false
      t.string :proposal_hash, null: false
      t.string :otp_confirmation_hash, null: false
      t.datetime :accepted_at, null: false
      t.jsonb :evidence, null: false, default: {}

      t.timestamps
    end

    add_index :commercial_contract_acceptances, :acceptance_token, unique: true, name: "idx_contract_acceptances_token"
    add_index :commercial_contract_acceptances, :proposal_id, unique: true, name: "idx_contract_acceptances_proposal"
    add_index :commercial_contract_acceptances, [:tenant_id, :accepted_at], name: "idx_contract_acceptances_tenant_accepted"

    create_table :commercial_contract_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :proposal, null: false, foreign_key: { to_table: :commercial_contract_proposals }
      t.references :admin_user, null: true, foreign_key: true
      t.string :event_type, null: false
      t.string :ip_address
      t.text :user_agent
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :commercial_contract_events, [:proposal_id, :created_at], name: "idx_contract_events_proposal_created"
    add_index :commercial_contract_events, [:tenant_id, :event_type], name: "idx_contract_events_tenant_type"
  end
end

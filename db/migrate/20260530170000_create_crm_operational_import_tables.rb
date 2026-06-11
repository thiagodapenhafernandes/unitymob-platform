class CreateCrmOperationalImportTables < ActiveRecord::Migration[7.1]
  def change
    create_table :client_interactions do |t|
      t.references :vista_import_batch, foreign_key: true
      t.string :source_table, null: false
      t.string :source_key, null: false
      t.references :proprietor, foreign_key: true
      t.references :habitation, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.string :vista_client_code
      t.string :vista_habitation_code
      t.string :vista_agent_code
      t.string :subject
      t.text :body
      t.string :interaction_type
      t.string :activity_type_id
      t.datetime :occurred_at
      t.datetime :return_at
      t.boolean :pending, null: false, default: false
      t.boolean :automatic, null: false, default: false
      t.boolean :lead, null: false, default: false
      t.boolean :launch, null: false, default: false
      t.string :acceptance
      t.string :visit_status
      t.string :lost_reason
      t.string :capture_vehicle
      t.bigint :proposal_value_cents
      t.string :business_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    create_table :habitation_interactions do |t|
      t.references :vista_import_batch, foreign_key: true
      t.string :source_table, null: false
      t.string :source_key, null: false
      t.references :habitation, foreign_key: true
      t.references :proprietor, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.string :vista_habitation_code
      t.string :vista_client_code
      t.string :vista_agent_code
      t.string :subject
      t.text :body
      t.string :interaction_type
      t.string :activity_type_id
      t.datetime :occurred_at
      t.datetime :started_at
      t.boolean :pending, null: false, default: false
      t.boolean :automatic, null: false, default: false
      t.boolean :private, null: false, default: false
      t.boolean :proposal, null: false, default: false
      t.string :status
      t.string :advertised
      t.string :published_vehicle
      t.string :key_requester
      t.bigint :proposal_value_cents
      t.string :business_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    create_table :crm_appointments do |t|
      t.references :vista_import_batch, foreign_key: true
      t.string :source_table, null: false
      t.string :source_key, null: false
      t.references :proprietor, foreign_key: true
      t.references :habitation, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.string :vista_client_code
      t.string :vista_habitation_code
      t.string :vista_agent_code
      t.string :title
      t.text :description
      t.string :appointment_type
      t.string :priority
      t.string :location
      t.datetime :starts_at
      t.datetime :ends_at
      t.datetime :completed_at
      t.datetime :created_in_source_at
      t.boolean :task, null: false, default: false
      t.boolean :completed, null: false, default: false
      t.boolean :all_day, null: false, default: false
      t.boolean :private, null: false, default: false
      t.boolean :deleted, null: false, default: false
      t.string :visit_status
      t.string :google_calendar_id
      t.string :business_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    create_table :client_property_interests do |t|
      t.references :vista_import_batch, foreign_key: true
      t.string :source_table, null: false
      t.string :source_key, null: false
      t.references :proprietor, foreign_key: true
      t.references :habitation, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.string :vista_client_code
      t.string :vista_habitation_code
      t.string :vista_agent_code
      t.string :interest_type
      t.string :status
      t.text :notes
      t.boolean :selected, null: false, default: false
      t.boolean :awaited, null: false, default: false
      t.boolean :lead, null: false, default: false
      t.datetime :started_at
      t.datetime :ended_at
      t.datetime :consulted_at
      t.datetime :last_search_at
      t.string :business_id
      t.jsonb :criteria, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :client_interactions, [:source_table, :source_key], unique: true
    add_index :client_interactions, [:vista_client_code, :occurred_at]
    add_index :client_interactions, [:vista_habitation_code, :occurred_at]
    add_index :client_interactions, :metadata, using: :gin

    add_index :habitation_interactions, [:source_table, :source_key], unique: true
    add_index :habitation_interactions, [:vista_habitation_code, :occurred_at]
    add_index :habitation_interactions, [:vista_client_code, :occurred_at]
    add_index :habitation_interactions, :metadata, using: :gin

    add_index :crm_appointments, [:source_table, :source_key], unique: true
    add_index :crm_appointments, [:vista_habitation_code, :starts_at]
    add_index :crm_appointments, [:vista_client_code, :starts_at]
    add_index :crm_appointments, :metadata, using: :gin

    add_index :client_property_interests, [:source_table, :source_key], unique: true
    add_index :client_property_interests, [:vista_client_code, :vista_habitation_code], name: "idx_cpi_client_habitation_codes"
    add_index :client_property_interests, :criteria, using: :gin
    add_index :client_property_interests, :metadata, using: :gin
  end
end

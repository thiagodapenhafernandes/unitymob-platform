class CreateCrmContactsFromVista < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_contacts do |t|
      t.references :vista_import_batch, foreign_key: true
      t.string :vista_code, null: false
      t.string :name, null: false
      t.string :email
      t.string :phone_primary
      t.string :mobile_phone
      t.string :residential_phone
      t.string :business_phone
      t.string :cpf_cnpj
      t.string :rg_ie
      t.string :contact_type
      t.boolean :is_client, null: false, default: false
      t.boolean :is_owner, null: false, default: false
      t.boolean :is_buyer, null: false, default: false
      t.boolean :is_referenced_owner, null: false, default: false
      t.string :capture_vehicle
      t.datetime :registered_at
      t.text :notes
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :crm_contacts, :vista_code, unique: true
    add_index :crm_contacts, [:is_owner, :is_referenced_owner]
    add_index :crm_contacts, :metadata, using: :gin

    add_reference :client_interactions, :crm_contact, foreign_key: true
    add_reference :habitation_interactions, :crm_contact, foreign_key: true
    add_reference :crm_appointments, :crm_contact, foreign_key: true
    add_reference :client_property_interests, :crm_contact, foreign_key: true
  end
end

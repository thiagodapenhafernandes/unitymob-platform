class AddHighValueVistaFieldsToImportTargets < ActiveRecord::Migration[7.1]
  def change
    change_table :crm_contacts, bulk: true do |t|
      t.string :source_status
      t.datetime :source_updated_at
      t.bigint :potential_value_cents
      t.boolean :favorite, null: false, default: false
      t.boolean :restricted, null: false, default: false
      t.boolean :receive_information, null: false, default: false
      t.boolean :show_email_to_client, null: false, default: false
      t.boolean :show_phone_on_web, null: false, default: false
    end

    change_table :proprietors, bulk: true do |t|
      t.string :source_status
      t.datetime :source_updated_at
      t.bigint :potential_value_cents
      t.boolean :favorite, null: false, default: false
      t.boolean :restricted, null: false, default: false
      t.boolean :receive_information, null: false, default: false
      t.boolean :show_email_to_client, null: false, default: false
      t.boolean :show_phone_on_web, null: false, default: false
      t.date :spouse_birth_date
    end

    change_table :admin_users, bulk: true do |t|
      t.boolean :vista_agenciador, null: false, default: false
      t.date :source_created_on
      t.date :source_departed_on
      t.datetime :last_login_at
      t.string :source_photo_path
      t.string :cpf_cnpj
      t.string :rg_ie
      t.string :nationality
      t.string :gender
      t.string :marital_status
      t.string :address_type
      t.string :street
      t.string :number
      t.string :complement
      t.string :neighborhood
      t.string :secondary_phone
      t.string :team_code
      t.integer :capture_goal
      t.integer :rental_capture_goal
      t.bigint :sales_goal_cents
    end

    change_table :crm_appointments, bulk: true do |t|
      t.integer :reminder_minutes
      t.boolean :sms_client, null: false, default: false
      t.boolean :sms_owner, null: false, default: false
      t.boolean :synced_with_source, null: false, default: false
      t.datetime :source_updated_at
    end

    change_table :habitation_broker_assignments, bulk: true do |t|
      t.datetime :source_created_at
      t.decimal :sale_commission_percentage, precision: 10, scale: 2
      t.decimal :rental_commission_percentage, precision: 10, scale: 2
      t.decimal :rental_cancellation_commission_percentage, precision: 10, scale: 2
      t.bigint :sale_commission_cents
      t.bigint :rental_commission_cents
      t.bigint :rental_cancellation_commission_cents
    end

    add_index :crm_contacts, :source_status
    add_index :crm_contacts, :potential_value_cents
    add_index :proprietors, :source_status
    add_index :admin_users, :team_code
    add_index :crm_appointments, :source_updated_at
  end
end

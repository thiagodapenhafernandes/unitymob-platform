class CreateWhatsappBusinessIntegrations < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_business_integrations do |t|
      t.references :connected_by_admin_user, foreign_key: { to_table: :admin_users }
      t.string :waba_id
      t.string :phone_number_id
      t.string :business_id
      t.text :access_token
      t.string :status, null: false, default: "disconnected"
      t.string :last_event
      t.string :last_error_code
      t.string :last_error_message
      t.string :meta_session_id
      t.datetime :connected_at
      t.datetime :token_expires_at
      t.jsonb :signup_payload, null: false, default: {}

      t.timestamps
    end

    add_index :whatsapp_business_integrations, :waba_id
    add_index :whatsapp_business_integrations, :phone_number_id
    add_index :whatsapp_business_integrations, :status
  end
end

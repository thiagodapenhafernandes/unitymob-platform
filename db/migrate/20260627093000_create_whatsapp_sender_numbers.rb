class CreateWhatsappSenderNumbers < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_sender_numbers do |t|
      t.references :whatsapp_business_integration, null: true, foreign_key: true
      t.string :label, null: false
      t.string :display_phone_number, null: false
      t.string :phone_number_id, null: false
      t.string :waba_id
      t.string :verified_name
      t.string :quality_rating
      t.string :status, null: false, default: "connected"
      t.boolean :active, null: false, default: true
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :whatsapp_sender_numbers, :phone_number_id, unique: true
    add_index :whatsapp_sender_numbers, :active
    add_index :whatsapp_sender_numbers, :status
  end
end

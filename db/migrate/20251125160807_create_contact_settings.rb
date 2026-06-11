class CreateContactSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :contact_settings do |t|
      t.string :whatsapp_primary
      t.string :whatsapp_secondary
      t.string :phone
      t.string :email_primary
      t.string :email_commercial
      t.text :address
      t.text :business_hours
      t.string :facebook_url
      t.string :instagram_url
      t.string :youtube_url
      t.string :linkedin_url

      t.timestamps
    end
  end
end

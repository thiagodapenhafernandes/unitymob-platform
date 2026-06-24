class CreateEmailSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :email_settings do |t|
      t.boolean :enabled, default: false, null: false
      t.string  :smtp_address
      t.integer :smtp_port, default: 587, null: false
      t.string  :smtp_domain
      t.string  :smtp_user_name
      t.text    :smtp_password # criptografado via Active Record Encryption
      t.string  :smtp_authentication, default: "plain"
      t.boolean :smtp_enable_starttls_auto, default: true, null: false
      t.string  :from_name
      t.string  :from_email
      t.string  :reply_to

      t.timestamps
    end
  end
end

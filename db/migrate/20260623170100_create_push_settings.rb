class CreatePushSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :push_settings do |t|
      t.boolean :enabled, default: false, null: false
      t.text    :vapid_public_key
      t.text    :vapid_private_key # criptografado via Active Record Encryption
      t.string  :subject_email

      t.timestamps
    end
  end
end

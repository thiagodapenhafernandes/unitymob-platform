class CreateStorageIntegrationSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :storage_integration_settings do |t|
      t.string :photo_provider, null: false, default: "local"
      t.string :document_provider, null: false, default: "local"
      t.boolean :public_photos_enabled, null: false, default: true

      t.string :do_spaces_bucket
      t.string :do_spaces_region, null: false, default: "sfo3"
      t.string :do_spaces_endpoint, null: false, default: "https://sfo3.digitaloceanspaces.com"
      t.string :do_spaces_public_base_url
      t.text :do_spaces_access_key_id_ciphertext
      t.text :do_spaces_secret_access_key_ciphertext

      t.string :s3_bucket
      t.string :s3_region, null: false, default: "us-east-1"
      t.string :s3_endpoint
      t.string :s3_public_base_url
      t.text :s3_access_key_id_ciphertext
      t.text :s3_secret_access_key_ciphertext

      t.datetime :last_tested_at
      t.string :last_test_status
      t.text :last_test_message

      t.timestamps
    end
  end
end

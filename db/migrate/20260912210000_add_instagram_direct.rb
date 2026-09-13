class AddInstagramDirect < ActiveRecord::Migration[7.1]
  def change
    add_column :meta_facebook_pages, :instagram_id, :string
    add_column :meta_facebook_pages, :instagram_username, :string
    add_column :meta_facebook_pages, :instagram_enabled, :boolean, default: false, null: false
    add_column :meta_facebook_pages, :instagram_received_at, :datetime
    add_index :meta_facebook_pages, :instagram_id, unique: true, where: "instagram_enabled = true", name: "index_active_instagram_profile"
    add_column :leads, :instagram_account_id, :string
    add_column :leads, :instagram_scoped_id, :string
    add_index :leads, [:tenant_id, :instagram_account_id, :instagram_scoped_id], unique: true, name: "index_leads_instagram_identity"
    create_table :instagram_messages do |t|
      t.references :lead, null: false, foreign_key: true
      t.string :message_id, null: false
      t.text :body
      t.jsonb :context, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :instagram_messages, [:lead_id, :message_id], unique: true
  end
end

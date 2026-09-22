class CreateInAppNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :in_app_notifications do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :title, null: false
      t.text :body
      t.string :url
      t.jsonb :metadata, null: false, default: {}
      t.datetime :read_at
      t.timestamps
    end

    add_index :in_app_notifications, [:admin_user_id, :read_at]
  end
end

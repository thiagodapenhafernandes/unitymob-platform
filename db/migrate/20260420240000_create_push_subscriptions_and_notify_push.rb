class CreatePushSubscriptionsAndNotifyPush < ActiveRecord::Migration[7.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :p256dh,   null: false
      t.string :auth,     null: false
      t.string :platform  # "web", "android", "ios"
      t.string :user_agent
      t.datetime :last_seen_at
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :push_subscriptions, [:admin_user_id, :endpoint], unique: true
    add_index :push_subscriptions, :active

    add_column :distribution_rules, :notify_push, :boolean, default: false, null: false
  end
end

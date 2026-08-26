# frozen_string_literal: true

class CreateAccountRoutes < ActiveRecord::Migration[7.1]
  def change
    create_table :account_routes do |t|
      t.string :email, null: false
      t.string :tenant_name
      t.string :target_url, null: false
      t.boolean :active, null: false, default: true
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :account_routes, :email, unique: true
    add_index :account_routes, :active
  end
end

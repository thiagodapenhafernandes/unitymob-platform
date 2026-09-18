# frozen_string_literal: true

class CreateWebhookMirrors < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_mirrors do |t|
      t.string :name, null: false
      t.string :provider, null: false, default: "all"
      t.string :target_url, null: false
      t.string :forwarding_secret, null: false
      t.boolean :active, null: false, default: false
      t.string :last_status
      t.text :last_error
      t.datetime :last_attempted_at
      t.datetime :last_succeeded_at

      t.timestamps
    end

    add_index :webhook_mirrors, :name, unique: true
    add_index :webhook_mirrors, %i[provider active]
  end
end

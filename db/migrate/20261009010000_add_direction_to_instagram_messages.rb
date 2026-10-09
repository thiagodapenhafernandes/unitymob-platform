# frozen_string_literal: true

class AddDirectionToInstagramMessages < ActiveRecord::Migration[7.1]
  def change
    change_table :instagram_messages, bulk: true do |t|
      t.string :direction, null: false, default: "inbound"
      t.references :sent_by_admin_user, foreign_key: { to_table: :admin_users }, index: true
    end
  end
end

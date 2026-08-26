# frozen_string_literal: true

class AddJtiToAdminUsers < ActiveRecord::Migration[7.1]
  def up
    add_column :admin_users, :jti, :string

    say_with_time "Backfilling jti for existing admin_users" do
      AdminUser.reset_column_information
      AdminUser.unscoped.where(jti: nil).find_each do |admin_user|
        admin_user.update_column(:jti, SecureRandom.uuid)
      end
    end

    change_column_null :admin_users, :jti, false
    add_index :admin_users, :jti, unique: true
  end

  def down
    remove_index :admin_users, :jti
    remove_column :admin_users, :jti
  end
end

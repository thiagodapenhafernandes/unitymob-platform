# frozen_string_literal: true

class AddSessionRevokedAtToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :session_revoked_at, :datetime
  end
end

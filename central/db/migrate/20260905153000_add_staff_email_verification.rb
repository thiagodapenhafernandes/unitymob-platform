class AddStaffEmailVerification < ActiveRecord::Migration[7.1]
  def change
    add_column :staffs, :verification_method, :string, null: false, default: 'totp'
    add_column :staffs, :email_code_digest, :string
    add_column :staffs, :email_challenge_digest, :string
    add_column :staffs, :email_code_expires_at, :datetime
    add_column :staffs, :email_code_sent_at, :datetime
    add_column :staffs, :email_code_attempts, :integer, null: false, default: 0
  end
end

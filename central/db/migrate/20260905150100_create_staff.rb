class CreateStaff < ActiveRecord::Migration[7.1]
  def change
    create_table :staffs do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :role, null: false
      t.string :password_digest
      t.text :otp_secret
      t.bigint :otp_consumed_at
      t.boolean :active, null: false, default: true
      t.integer :session_version, null: false, default: 0
      t.datetime :activated_at
      t.string :activation_digest
      t.datetime :activation_expires_at
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_until
      t.timestamps
    end
    add_index :staffs, "lower(email)", unique: true
    add_index :staffs, :activation_digest, unique: true
    add_foreign_key :support_tickets, :staffs, column: :assignee_id
  end
end

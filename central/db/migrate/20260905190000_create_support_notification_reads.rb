class CreateSupportNotificationReads < ActiveRecord::Migration[7.1]
  def change
    create_table :support_notification_reads do |t|
      t.references :staff, null: false, foreign_key: true
      t.references :ticket, null: false, foreign_key: { to_table: :support_tickets }
      t.bigint :message_id, null: false
      t.timestamps
    end
    add_index :support_notification_reads, [:staff_id, :ticket_id], unique: true
  end
end

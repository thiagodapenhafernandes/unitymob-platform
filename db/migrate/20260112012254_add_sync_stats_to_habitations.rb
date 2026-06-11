class AddSyncStatsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :last_sync_at, :datetime
    add_column :habitations, :last_sync_status, :string
    add_column :habitations, :last_sync_message, :text
  end
end

class AddNotificationEventsToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    # Eventos extras de notificação ao corretor (push), além da distribuição normal.
    add_column :lead_settings, :notify_on_direct_assignment, :boolean, default: true,  null: false
    add_column :lead_settings, :notify_on_reassignment,      :boolean, default: true,  null: false
    add_column :lead_settings, :notify_on_lost_turn,         :boolean, default: false, null: false
  end
end

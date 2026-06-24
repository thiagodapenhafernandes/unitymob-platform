class AddDistributionNotifyTogglesToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    # Eventos de distribuição (já notificavam; agora viram toggles, default ON).
    add_column :lead_settings, :notify_on_distribution,   :boolean, default: true, null: false # rotativo/performance
    add_column :lead_settings, :notify_on_sticky,         :boolean, default: true, null: false # fidelização
    add_column :lead_settings, :notify_on_redistribution, :boolean, default: true, null: false # reenvio pós-pocket
  end
end

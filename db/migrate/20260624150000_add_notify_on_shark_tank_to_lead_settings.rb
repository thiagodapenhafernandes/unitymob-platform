class AddNotifyOnSharkTankToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    # Shark Tank: notifica todos os corretores da regra; o 1º que aceitar vira dono.
    add_column :lead_settings, :notify_on_shark_tank, :boolean, default: true, null: false
  end
end

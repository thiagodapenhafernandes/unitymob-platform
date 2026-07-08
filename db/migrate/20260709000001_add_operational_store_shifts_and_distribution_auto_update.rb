class AddOperationalStoreShiftsAndDistributionAutoUpdate < ActiveRecord::Migration[7.1]
  def change
    add_column :stores, :turnos_config, :jsonb, null: false, default: {}
    add_index :stores, :turnos_config, using: :gin

    add_column :check_ins, :turno, :string
    add_column :check_ins, :status_chegada, :string
    add_index :check_ins, [:store_id, :turno, :status_chegada, :checked_in_at],
              name: "idx_checkins_store_turno_status_date"

    add_column :distribution_rules, :auto_update_agents_enabled, :boolean, null: false, default: false
    add_column :distribution_rules, :auto_update_trigger, :string, array: true, null: false, default: ["sorteio"]
    add_column :distribution_rules, :auto_update_shuffle_agents, :boolean, null: false, default: false
    add_index :distribution_rules, :auto_update_trigger, using: :gin
    add_index :distribution_rules, [:tenant_id, :auto_update_agents_enabled],
              name: "idx_distribution_rules_tenant_auto_update"
  end
end

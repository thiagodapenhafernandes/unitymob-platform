class AddCheckinFlagsToDistributionRules < ActiveRecord::Migration[7.1]
  # Integração com o módulo field: regras de distribuição podem exigir que o
  # corretor tenha check-in ativo. Default false para retrocompatibilidade total.
  def change
    add_column :distribution_rules, :require_active_checkin, :boolean, default: false, null: false
    add_column :distribution_rules, :require_inside_radius, :boolean, default: false, null: false
    add_column :distribution_rules, :exclude_suspicious_checkins, :boolean, default: true, null: false
    add_reference :distribution_rules, :checkin_store, foreign_key: { to_table: :stores }
  end
end

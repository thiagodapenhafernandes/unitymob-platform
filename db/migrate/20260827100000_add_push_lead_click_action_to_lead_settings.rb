# frozen_string_literal: true

# "Ao tocar na notificação" morava só em PushSetting (tabela global, sem
# tenant_id) — qualquer conta que mudasse isso afetava a plataforma inteira.
# lead_settings já é por tenant; movemos o campo pra cá de vez, preservando o
# comportamento atual de cada conta (backfill com o valor global vigente).
class AddPushLeadClickActionToLeadSettings < ActiveRecord::Migration[7.1]
  def up
    add_column :lead_settings, :push_lead_click_action, :string, null: false, default: "system"

    current_global_value = safe_current_global_click_action
    execute <<~SQL.squish
      UPDATE lead_settings SET push_lead_click_action = #{quote(current_global_value)}
    SQL
  end

  def down
    remove_column :lead_settings, :push_lead_click_action
  end

  private

  # PushSetting pode não existir ainda (deploy incremental) ou a coluna
  # lead_click_action pode estar vazia — cai no mesmo fallback que
  # PushSetting#lead_click_action_value já usa ("system").
  def safe_current_global_click_action
    value = execute("SELECT lead_click_action FROM push_settings ORDER BY id LIMIT 1").first&.fetch("lead_click_action", nil)
    value.presence_in(%w[system whatsapp]) || "system"
  rescue ActiveRecord::StatementInvalid
    "system"
  end
end

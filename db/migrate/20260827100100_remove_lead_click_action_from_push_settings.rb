# frozen_string_literal: true

# Campo substituído por lead_settings.push_lead_click_action (por tenant —
# ver 20260827100000_add_push_lead_click_action_to_lead_settings.rb). Nenhuma
# tela de admin renderiza mais este campo global; só sobrava o parâmetro
# permitido nos controllers, já removido junto com esta migration.
class RemoveLeadClickActionFromPushSettings < ActiveRecord::Migration[7.1]
  def up
    remove_column :push_settings, :lead_click_action if column_exists?(:push_settings, :lead_click_action)
  end

  def down
    add_column :push_settings, :lead_click_action, :string, default: "whatsapp", null: false unless column_exists?(:push_settings, :lead_click_action)
  end
end

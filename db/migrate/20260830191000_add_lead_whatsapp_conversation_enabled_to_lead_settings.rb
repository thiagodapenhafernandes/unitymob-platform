# frozen_string_literal: true

class AddLeadWhatsappConversationEnabledToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_settings, :lead_whatsapp_conversation_enabled, :boolean, null: false, default: true
  end
end

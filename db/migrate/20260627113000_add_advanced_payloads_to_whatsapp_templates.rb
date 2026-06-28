class AddAdvancedPayloadsToWhatsappTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_templates, :carousel_cards, :jsonb, null: false, default: []
    add_column :whatsapp_templates, :flow_config, :jsonb, null: false, default: {}
  end
end

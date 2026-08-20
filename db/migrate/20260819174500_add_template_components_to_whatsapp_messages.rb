class AddTemplateComponentsToWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_messages, :template_components, :jsonb, null: false, default: []
  end
end

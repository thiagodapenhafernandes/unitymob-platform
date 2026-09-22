class AddUsageContextToWhatsappTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_templates, :usage_context, :string, null: false, default: "broadcast"
    add_index :whatsapp_templates, [:tenant_id, :usage_context]
  end
end

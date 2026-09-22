class CreateWhatsappResponseFlows < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_response_flows do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :whatsapp_template, null: false, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :admin_users }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.jsonb :button_actions, null: false, default: {}

      t.timestamps
    end

    add_index :whatsapp_response_flows, [:tenant_id, :whatsapp_template_id], unique: true, name: "idx_wa_response_flows_template"
    add_index :whatsapp_response_flows, [:tenant_id, :active]
  end
end

class CreateWhatsappAttendances < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_attendances do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :whatsapp_conversation, null: false, foreign_key: true
      t.references :whatsapp_response_flow, foreign_key: { on_delete: :nullify }
      t.references :lead, foreign_key: { on_delete: :nullify }
      t.references :distribution_rule, foreign_key: { on_delete: :nullify }
      t.references :admin_user, foreign_key: { on_delete: :nullify }
      t.references :closed_by, foreign_key: { to_table: :admin_users, on_delete: :nullify }
      t.string :button_key
      t.string :button_text
      t.jsonb :agent_ids, null: false, default: []
      t.string :status, null: false, default: "open"
      t.text :finish_message
      t.string :close_reason
      t.jsonb :pending_switch, null: false, default: {}
      t.datetime :opened_at, null: false
      t.datetime :accepted_at
      t.datetime :closed_at
      t.timestamps
    end

    # Um único atendimento aberto por conversa (número de telefone).
    add_index :whatsapp_attendances, :whatsapp_conversation_id,
              unique: true, where: "status = 'open'", name: "index_whatsapp_attendances_one_open_per_conversation"
  end
end

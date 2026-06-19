class CreateWhatsappTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_templates do |t|
      t.string :name, null: false
      t.string :language, null: false, default: "pt_BR"
      t.string :category
      t.text :body
      t.jsonb :variables, null: false, default: []
      t.string :status
      t.string :meta_id

      t.timestamps
    end

    add_index :whatsapp_templates, [:name, :language], unique: true
  end
end

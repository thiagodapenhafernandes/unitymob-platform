class CreatePublicForms < ActiveRecord::Migration[7.1]
  def change
    create_table :public_forms do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :category, null: false, default: "custom"
      t.string :title, null: false
      t.text :subtitle
      t.string :submit_label, null: false, default: "Enviar"
      t.string :success_message, null: false, default: "Mensagem enviada com sucesso."
      t.string :redirect_url
      t.boolean :active, null: false, default: true
      t.boolean :modal_enabled, null: false, default: true
      t.jsonb :modal_config, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :public_forms, [:tenant_id, :slug], unique: true
    add_index :public_forms, [:tenant_id, :category]
    add_index :public_forms, [:tenant_id, :active]

    create_table :public_form_fields do |t|
      t.references :public_form, null: false, foreign_key: true
      t.string :field_type, null: false
      t.string :name, null: false
      t.string :label, null: false
      t.string :placeholder
      t.text :hint
      t.boolean :required, null: false, default: false
      t.integer :position, null: false, default: 0
      t.jsonb :options, null: false, default: []
      t.jsonb :config, null: false, default: {}

      t.timestamps
    end

    add_index :public_form_fields, [:public_form_id, :name], unique: true
    add_index :public_form_fields, [:public_form_id, :position]

    create_table :public_form_submissions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :public_form, null: false, foreign_key: true
      t.jsonb :payload, null: false, default: {}
      t.jsonb :source, null: false, default: {}
      t.string :normalized_name
      t.string :normalized_email
      t.string :normalized_phone
      t.string :status, null: false, default: "received"

      t.timestamps
    end

    add_index :public_form_submissions, [:tenant_id, :created_at]
    add_index :public_form_submissions, [:public_form_id, :created_at]
    add_index :public_form_submissions, :normalized_phone
    add_index :public_form_submissions, :normalized_email
  end
end

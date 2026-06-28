class AddMetaSubmissionFieldsToWhatsappTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_templates, :template_type, :string, null: false, default: "text"
    add_column :whatsapp_templates, :allow_category_change, :boolean, null: false, default: false
    add_column :whatsapp_templates, :header_format, :string, null: false, default: "none"
    add_column :whatsapp_templates, :header_text, :string
    add_column :whatsapp_templates, :header_media_handle, :string
    add_column :whatsapp_templates, :footer_text, :string
    add_column :whatsapp_templates, :buttons, :jsonb, null: false, default: []
    add_column :whatsapp_templates, :example_values, :jsonb, null: false, default: []
    add_column :whatsapp_templates, :components, :jsonb, null: false, default: []
    add_column :whatsapp_templates, :submission_error, :text

    add_index :whatsapp_templates, :template_type
    add_index :whatsapp_templates, :status
  end
end

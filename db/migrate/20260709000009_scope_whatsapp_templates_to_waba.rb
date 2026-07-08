class ScopeWhatsappTemplatesToWaba < ActiveRecord::Migration[7.1]
  def up
    add_column :whatsapp_templates, :waba_id, :string

    execute <<~SQL.squish
      UPDATE whatsapp_templates
         SET waba_id = whatsapp_business_integrations.waba_id
        FROM whatsapp_business_integrations
       WHERE whatsapp_templates.tenant_id = whatsapp_business_integrations.tenant_id
         AND whatsapp_templates.waba_id IS NULL
         AND whatsapp_business_integrations.waba_id IS NOT NULL
    SQL

    remove_index :whatsapp_templates, name: :index_whatsapp_templates_on_tenant_id_and_name_and_language if index_exists?(:whatsapp_templates, [:tenant_id, :name, :language], name: :index_whatsapp_templates_on_tenant_id_and_name_and_language)
    add_index :whatsapp_templates, [:tenant_id, :waba_id, :name, :language],
              unique: true,
              name: :idx_whatsapp_templates_on_tenant_waba_name_language
    add_index :whatsapp_templates, [:tenant_id, :waba_id, :status],
              name: :idx_whatsapp_templates_on_tenant_waba_status
  end

  def down
    remove_index :whatsapp_templates, name: :idx_whatsapp_templates_on_tenant_waba_status if index_exists?(:whatsapp_templates, [:tenant_id, :waba_id, :status], name: :idx_whatsapp_templates_on_tenant_waba_status)
    remove_index :whatsapp_templates, name: :idx_whatsapp_templates_on_tenant_waba_name_language if index_exists?(:whatsapp_templates, [:tenant_id, :waba_id, :name, :language], name: :idx_whatsapp_templates_on_tenant_waba_name_language)
    add_index :whatsapp_templates, [:tenant_id, :name, :language], unique: true unless index_exists?(:whatsapp_templates, [:tenant_id, :name, :language])
    remove_column :whatsapp_templates, :waba_id
  end
end

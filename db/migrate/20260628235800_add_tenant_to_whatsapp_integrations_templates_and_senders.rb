class AddTenantToWhatsappIntegrationsTemplatesAndSenders < ActiveRecord::Migration[7.1]
  def up
    default_tenant = Tenant.default

    add_reference :whatsapp_business_integrations, :tenant, null: true, foreign_key: true, index: true
    add_reference :whatsapp_templates, :tenant, null: true, foreign_key: true, index: true
    add_reference :whatsapp_sender_numbers, :tenant, null: true, foreign_key: true, index: true

    WhatsappBusinessIntegration.reset_column_information
    WhatsappTemplate.reset_column_information
    WhatsappSenderNumber.reset_column_information

    WhatsappBusinessIntegration.where(tenant_id: nil).update_all(tenant_id: default_tenant.id)
    WhatsappTemplate.where(tenant_id: nil).update_all(tenant_id: default_tenant.id)
    WhatsappSenderNumber.where(tenant_id: nil).update_all(tenant_id: default_tenant.id)

    change_column_null :whatsapp_business_integrations, :tenant_id, false
    change_column_null :whatsapp_templates, :tenant_id, false
    change_column_null :whatsapp_sender_numbers, :tenant_id, false

    remove_index :whatsapp_templates, name: :index_whatsapp_templates_on_name_and_language if index_exists?(:whatsapp_templates, [:name, :language], name: :index_whatsapp_templates_on_name_and_language)

    add_index :whatsapp_business_integrations, [:tenant_id, :status]
    add_index :whatsapp_business_integrations, [:tenant_id, :phone_number_id]
    add_index :whatsapp_templates, [:tenant_id, :name, :language], unique: true
    add_index :whatsapp_templates, [:tenant_id, :status]
    add_index :whatsapp_sender_numbers, [:tenant_id, :active]
    add_index :whatsapp_sender_numbers, [:tenant_id, :status]
  end

  def down
    remove_index :whatsapp_sender_numbers, [:tenant_id, :status] if index_exists?(:whatsapp_sender_numbers, [:tenant_id, :status])
    remove_index :whatsapp_sender_numbers, [:tenant_id, :active] if index_exists?(:whatsapp_sender_numbers, [:tenant_id, :active])
    remove_index :whatsapp_templates, [:tenant_id, :status] if index_exists?(:whatsapp_templates, [:tenant_id, :status])
    remove_index :whatsapp_templates, [:tenant_id, :name, :language] if index_exists?(:whatsapp_templates, [:tenant_id, :name, :language])
    remove_index :whatsapp_business_integrations, [:tenant_id, :phone_number_id] if index_exists?(:whatsapp_business_integrations, [:tenant_id, :phone_number_id])
    remove_index :whatsapp_business_integrations, [:tenant_id, :status] if index_exists?(:whatsapp_business_integrations, [:tenant_id, :status])

    add_index :whatsapp_templates, [:name, :language], unique: true, name: :index_whatsapp_templates_on_name_and_language unless index_exists?(:whatsapp_templates, [:name, :language], name: :index_whatsapp_templates_on_name_and_language)

    remove_reference :whatsapp_sender_numbers, :tenant, foreign_key: true
    remove_reference :whatsapp_templates, :tenant, foreign_key: true
    remove_reference :whatsapp_business_integrations, :tenant, foreign_key: true
  end
end

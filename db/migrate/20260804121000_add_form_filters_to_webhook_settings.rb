class AddFormFiltersToWebhookSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :webhook_settings, :form_delivery_scope, :string, null: false, default: "all"
    add_column :webhook_settings, :form_categories, :jsonb, null: false, default: []
    add_column :webhook_settings, :public_form_ids, :jsonb, null: false, default: []

    add_index :webhook_settings, :form_delivery_scope
  end
end

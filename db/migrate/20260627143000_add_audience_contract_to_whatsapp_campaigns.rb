class AddAudienceContractToWhatsappCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_campaigns, :audience_mode, :string, null: false, default: "filters"
    add_column :whatsapp_campaigns, :audience_definition, :jsonb, null: false, default: {}
    add_column :whatsapp_campaigns, :import_batch_size, :integer, null: false, default: 300
    add_column :whatsapp_campaigns, :import_interval_minutes, :integer, null: false, default: 1
    add_column :whatsapp_campaigns, :import_status, :string
    add_column :whatsapp_campaigns, :import_total_rows, :integer, null: false, default: 0
    add_column :whatsapp_campaigns, :import_valid_rows, :integer, null: false, default: 0
    add_column :whatsapp_campaigns, :import_invalid_rows, :integer, null: false, default: 0
    add_column :whatsapp_campaigns, :import_last_error, :text

    add_index :whatsapp_campaigns, :audience_mode
    add_index :whatsapp_campaigns, :audience_definition, using: :gin
  end
end

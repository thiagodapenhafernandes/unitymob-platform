class AddSenderAndGroupToWhatsappCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_reference :whatsapp_campaigns, :whatsapp_sender_number, null: true, foreign_key: true
    add_column :whatsapp_campaigns, :group_name, :string

    add_index :whatsapp_campaigns, :group_name
  end
end

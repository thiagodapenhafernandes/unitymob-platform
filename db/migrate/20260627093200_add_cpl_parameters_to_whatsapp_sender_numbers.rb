class AddCplParametersToWhatsappSenderNumbers < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_sender_numbers, :cpl_sent_unit_price, :decimal, precision: 10, scale: 2, null: false, default: "0.59"
    add_column :whatsapp_sender_numbers, :cpl_fla_unit_price, :decimal, precision: 10, scale: 2, null: false, default: "0.12"
  end
end

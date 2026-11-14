class AddMetaExchangeRateToWhatsappSenderNumbers < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_sender_numbers, :meta_brl_exchange_rate, :decimal, precision: 18, scale: 8
    add_column :whatsapp_sender_numbers, :meta_exchange_currency, :string, limit: 3
    change_column_default :whatsapp_sender_numbers, :cpl_sent_unit_price, from: 0.59, to: 0
    add_check_constraint :whatsapp_sender_numbers, "meta_brl_exchange_rate IS NULL OR (meta_brl_exchange_rate > 0 AND meta_brl_exchange_rate < 1000000 AND meta_exchange_currency IS NOT NULL AND meta_exchange_currency ~ '^[A-Z]{3}$')", name: "whatsapp_sender_meta_exchange_rate_positive"
  end
end

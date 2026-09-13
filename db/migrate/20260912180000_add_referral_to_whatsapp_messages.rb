class AddReferralToWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_messages, :referral, :jsonb, default: {}, null: false
  end
end

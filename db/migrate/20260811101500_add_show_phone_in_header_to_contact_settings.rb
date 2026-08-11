class AddShowPhoneInHeaderToContactSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :contact_settings, :show_phone_in_header, :boolean, null: false, default: true
  end
end

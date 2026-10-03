class AddPublicCardSettingsToPropertySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :property_settings, :card_cta_enabled, :boolean, default: true, null: false
    add_column :property_settings, :card_cta_title, :string, default: "Gostou deste imóvel?", null: false
    add_column :property_settings, :card_cta_label, :string, default: "Ver mais fotos", null: false
  end
end

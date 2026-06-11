class AddHeroFieldsToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :hero_cta_text, :string
    add_column :home_settings, :hero_cta_link, :string
    add_column :home_settings, :overlay_opacity, :decimal
  end
end

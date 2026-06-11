class AddHeroButtonColorsToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :hero_button_color, :string
  end
end

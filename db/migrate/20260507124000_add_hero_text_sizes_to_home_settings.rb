class AddHeroTextSizesToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :hero_title_font_size, :integer
    add_column :home_settings, :hero_subtitle_font_size, :integer
  end
end

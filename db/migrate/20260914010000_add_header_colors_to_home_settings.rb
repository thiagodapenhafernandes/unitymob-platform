class AddHeaderColorsToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :header_colors, :jsonb, default: {}, null: false
  end
end

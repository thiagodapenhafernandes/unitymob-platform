class AddAccentColorToLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :layout_settings, :accent_color, :string
  end
end

class AddSearchFilterDisplayModeToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :search_filter_display_mode, :string, null: false, default: "hero"
  end
end

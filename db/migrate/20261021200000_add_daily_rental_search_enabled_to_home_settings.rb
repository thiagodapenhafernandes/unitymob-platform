class AddDailyRentalSearchEnabledToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :daily_rental_search_enabled, :boolean, default: false, null: false
  end
end

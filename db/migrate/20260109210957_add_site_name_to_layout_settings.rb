class AddSiteNameToLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :layout_settings, :site_name, :string
  end
end

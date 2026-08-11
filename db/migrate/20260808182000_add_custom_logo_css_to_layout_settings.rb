class AddCustomLogoCssToLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :layout_settings, :custom_logo_css, :text
  end
end

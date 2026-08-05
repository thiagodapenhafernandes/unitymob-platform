class AddPublicHeaderCssToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :public_header_css, :text
  end
end

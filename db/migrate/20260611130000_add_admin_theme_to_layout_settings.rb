class AddAdminThemeToLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    # Cor primária do CRM (white-label por cliente). Independente da cor do site.
    add_column :layout_settings, :admin_primary_color, :string, default: "#365F8F", null: false
  end
end

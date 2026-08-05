class AddPublicSiteThemeToTenants < ActiveRecord::Migration[7.1]
  def change
    add_column :tenants, :public_site_theme, :string, null: false, default: "saluteimoveis"
  end
end

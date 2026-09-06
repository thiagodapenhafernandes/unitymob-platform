class AddTermsToBrowserExtensionGrants < ActiveRecord::Migration[7.1]
  def change
    add_column :browser_extension_grants, :terms_accepted_at, :datetime
    add_column :browser_extension_grants, :terms_version, :string
    add_column :browser_extension_grants, :terms_digest, :string
  end
end

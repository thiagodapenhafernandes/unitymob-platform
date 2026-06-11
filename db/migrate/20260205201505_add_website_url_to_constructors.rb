class AddWebsiteUrlToConstructors < ActiveRecord::Migration[7.1]
  def change
    add_column :constructors, :website_url, :string
  end
end

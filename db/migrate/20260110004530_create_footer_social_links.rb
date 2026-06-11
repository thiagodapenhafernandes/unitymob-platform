class CreateFooterSocialLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :footer_social_links do |t|
      t.string :platform
      t.string :url
      t.boolean :enabled
      t.integer :position

      t.timestamps
    end
  end
end

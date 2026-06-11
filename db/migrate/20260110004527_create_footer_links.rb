class CreateFooterLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :footer_links do |t|
      t.string :label
      t.string :url
      t.integer :position

      t.timestamps
    end
  end
end

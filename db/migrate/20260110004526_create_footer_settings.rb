class CreateFooterSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :footer_settings do |t|
      t.string :about_title
      t.text :about_text
      t.string :links_title
      t.string :stores_title
      t.string :contact_title
      t.string :social_title
      t.string :whatsapp
      t.string :email
      t.string :copyright_text

      t.timestamps
    end
  end
end

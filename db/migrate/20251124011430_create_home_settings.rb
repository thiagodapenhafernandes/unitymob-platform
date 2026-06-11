class CreateHomeSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :home_settings do |t|
      t.text :hero_title
      t.text :hero_subtitle
      t.text :cta_title
      t.text :cta_subtitle
      t.boolean :services_active
      t.boolean :why_choose_active
      t.boolean :cta_contact_active

      t.timestamps
    end
  end
end

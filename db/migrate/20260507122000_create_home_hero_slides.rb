class CreateHomeHeroSlides < ActiveRecord::Migration[7.1]
  def change
    create_table :home_hero_slides do |t|
      t.references :home_setting, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.string :alt_text

      t.timestamps
    end

    add_index :home_hero_slides, [:home_setting_id, :position]
  end
end

class CreatePropertySettings < ActiveRecord::Migration[7.1]
  def change
    create_table :property_settings do |t|
      t.string :watermark_position, null: false, default: "bottom_left"

      t.timestamps
    end
  end
end

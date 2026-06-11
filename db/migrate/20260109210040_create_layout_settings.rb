class CreateLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :layout_settings do |t|
      t.string :primary_color
      t.string :secondary_color

      t.timestamps
    end
  end
end

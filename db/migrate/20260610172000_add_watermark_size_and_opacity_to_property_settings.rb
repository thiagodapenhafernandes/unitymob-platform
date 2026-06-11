class AddWatermarkSizeAndOpacityToPropertySettings < ActiveRecord::Migration[7.1]
  def up
    add_column :property_settings, :watermark_size_percentage, :integer, null: false, default: 28
    add_column :property_settings, :watermark_opacity_percentage, :integer, null: false, default: 100

    execute <<~SQL.squish
      UPDATE property_settings
      SET watermark_size_percentage = 58
      WHERE watermark_position = 'center'
    SQL
  end

  def down
    remove_column :property_settings, :watermark_opacity_percentage
    remove_column :property_settings, :watermark_size_percentage
  end
end

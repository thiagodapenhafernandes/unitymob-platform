class AddFooterSettingToFooterModels < ActiveRecord::Migration[7.1]
  def change
    add_reference :footer_links, :footer_setting, null: false, foreign_key: true
    add_reference :footer_stores, :footer_setting, null: false, foreign_key: true
    add_reference :footer_social_links, :footer_setting, null: false, foreign_key: true
  end
end

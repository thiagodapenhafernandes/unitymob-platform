class AddTagsToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :tags, :jsonb, null: false, default: []
    add_index :leads, :tags, using: :gin
  end
end

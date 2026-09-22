class AddVideoFieldsToHomeSectionItems < ActiveRecord::Migration[7.1]
  def change
    add_column :home_section_items, :source_type, :string
    add_column :home_section_items, :source_url, :text
    add_column :home_section_items, :location, :string
    add_column :home_section_items, :price_label, :string
    add_column :home_section_items, :badges, :jsonb, null: false, default: []
  end
end

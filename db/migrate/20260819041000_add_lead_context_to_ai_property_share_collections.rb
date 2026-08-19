class AddLeadContextToAiPropertyShareCollections < ActiveRecord::Migration[7.1]
  def change
    add_reference :ai_property_share_collections, :lead, foreign_key: true, index: true
    add_column :ai_property_share_collections, :message, :text
  end
end

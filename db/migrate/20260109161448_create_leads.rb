class CreateLeads < ActiveRecord::Migration[7.1]
  def change
    create_table :leads do |t|
      t.string :name
      t.string :email
      t.string :phone
      t.integer :property_id
      t.string :source_url
      t.string :lead_type

      t.timestamps
    end
  end
end

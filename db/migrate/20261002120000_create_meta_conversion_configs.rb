class CreateMetaConversionConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :meta_conversion_configs do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.string :dataset_id, null: false, default: ""
      t.string :dataset_name
      t.string :test_event_code
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end
  end
end

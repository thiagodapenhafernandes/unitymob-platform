class ConvertMetaConversionConfigToDatasets < ActiveRecord::Migration[7.1]
  def up
    add_column :meta_conversion_configs, :datasets, :jsonb, null: false, default: []

    execute(<<~SQL.squish)
      UPDATE meta_conversion_configs
      SET datasets = jsonb_build_array(jsonb_build_object('id', dataset_id, 'name', COALESCE(NULLIF(dataset_name, ''), dataset_id)))
      WHERE dataset_id IS NOT NULL AND dataset_id <> ''
    SQL

    remove_column :meta_conversion_configs, :dataset_id
    remove_column :meta_conversion_configs, :dataset_name
  end

  def down
    add_column :meta_conversion_configs, :dataset_id, :string, null: false, default: ""
    add_column :meta_conversion_configs, :dataset_name, :string

    execute(<<~SQL.squish)
      UPDATE meta_conversion_configs
      SET dataset_id = COALESCE(datasets->0->>'id', ''),
          dataset_name = datasets->0->>'name'
    SQL

    remove_column :meta_conversion_configs, :datasets
  end
end

class UnifiedLandingPages < ActiveRecord::Migration[7.1]
  def change
    rename_column :landing_pages, :filters, :filter_params
    change_column_default :landing_pages, :filter_params, from: nil, to: {}
  end
end

class AddStatusAndNotesToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :status, :string
    add_column :leads, :notes, :text
  end
end

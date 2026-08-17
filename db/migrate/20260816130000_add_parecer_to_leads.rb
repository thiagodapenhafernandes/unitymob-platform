class AddParecerToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :parecer, :text
  end
end

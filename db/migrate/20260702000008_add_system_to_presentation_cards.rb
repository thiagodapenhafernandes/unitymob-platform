class AddSystemToPresentationCards < ActiveRecord::Migration[7.1]
  def change
    # Template de SISTEMA (nível tenant): admin_user_id nulo + system=true.
    change_column_null :presentation_cards, :admin_user_id, true
    add_column :presentation_cards, :system, :boolean, null: false, default: false
  end
end

class AddModalLayoutAndSizeToPublicForms < ActiveRecord::Migration[7.1]
  def change
    add_column :public_forms, :modal_layout, :string, default: "premium", null: false
    add_column :public_forms, :modal_size, :string, default: "xl", null: false
  end
end

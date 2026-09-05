class OrderSupportAccountControls < ActiveRecord::Migration[7.1]
  def change
    add_column :support_accounts, :control_revision, :integer, default: 0, null: false
  end
end

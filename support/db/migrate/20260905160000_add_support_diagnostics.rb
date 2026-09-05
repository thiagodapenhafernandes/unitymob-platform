class AddSupportDiagnostics < ActiveRecord::Migration[7.1]
  def change
    add_column :support_tickets, :diagnostics, :jsonb, null: false, default: {}
  end
end

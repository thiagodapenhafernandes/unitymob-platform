class AddRequireTwoFactorToTenants < ActiveRecord::Migration[7.1]
  # Toggle "exigir verificação em duas etapas de todos" por CONTA (Setting é
  # key-value global sem tenant — coluna no tenant é o escopo correto).
  def up
    unless column_exists?(:tenants, :require_two_factor)
      add_column :tenants, :require_two_factor, :boolean, null: false, default: false
    end
  end

  def down
    remove_column :tenants, :require_two_factor if column_exists?(:tenants, :require_two_factor)
  end
end

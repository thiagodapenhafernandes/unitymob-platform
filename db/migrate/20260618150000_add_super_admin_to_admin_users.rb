class AddSuperAdminToAdminUsers < ActiveRecord::Migration[7.1]
  # "Admin do Sistema": nível acima do Admin da Conta. Não é perfil nem entra no
  # organograma — é uma flag de operador da aplicação (métricas + impersonar qualquer um).
  def change
    add_column :admin_users, :super_admin, :boolean, default: false, null: false
    add_index :admin_users, :super_admin, where: "super_admin = true"
  end
end

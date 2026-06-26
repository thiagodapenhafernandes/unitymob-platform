class AddLeadsViewModeToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    # Preferência por usuário do modo de visualização da tela de leads
    # (kanban/list), lembrada entre sessões. Null = ainda não escolheu (cai no
    # padrão kanban).
    add_column :admin_users, :leads_view_mode, :string
  end
end

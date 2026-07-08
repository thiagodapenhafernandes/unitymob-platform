class AddRentalsManagerToAdminUsers < ActiveRecord::Migration[7.1]
  # Gestão por área de atuação: manager_id passa a ser oficialmente o gestor de
  # VENDA; rentals_manager_id é o gestor de LOCAÇÃO. Quem atua em "Ambos" tem os
  # dois vínculos (aparece nas duas equipes da hierarquia e nas duas árvores do
  # filtro de distribuição).
  def up
    add_column :admin_users, :rentals_manager_id, :bigint
    add_foreign_key :admin_users, :admin_users, column: :rentals_manager_id
    add_index :admin_users, :rentals_manager_id

    # Backfill fiel: quem atua SÓ em locação tinha o gestor guardado em
    # manager_id — move para o campo da área correta. (acting_type: 1 = rentals)
    execute <<~SQL
      UPDATE admin_users
         SET rentals_manager_id = manager_id, manager_id = NULL
       WHERE acting_type = 1 AND manager_id IS NOT NULL
    SQL

    # Quem atua em AMBOS herda o gestor atual também como gestor de locação
    # (ajustável depois no cadastro). (acting_type: 2 = both)
    execute <<~SQL
      UPDATE admin_users
         SET rentals_manager_id = manager_id
       WHERE acting_type = 2 AND manager_id IS NOT NULL AND rentals_manager_id IS NULL
    SQL
  end

  def down
    execute <<~SQL
      UPDATE admin_users
         SET manager_id = COALESCE(manager_id, rentals_manager_id)
    SQL
    remove_index :admin_users, :rentals_manager_id
    remove_foreign_key :admin_users, column: :rentals_manager_id
    remove_column :admin_users, :rentals_manager_id
  end
end

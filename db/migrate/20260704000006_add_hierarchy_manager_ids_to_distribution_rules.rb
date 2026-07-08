class AddHierarchyManagerIdsToDistributionRules < ActiveRecord::Migration[7.1]
  # Gestores escolhidos no filtro "Filtrar por gestor" da regra: antes era só
  # filtro visual (não persistia — reabrir a regra perdia a seleção). Agora a
  # regra guarda os gestores e o form restaura o filtro/equipe ao editar.
  def change
    add_column :distribution_rules, :hierarchy_manager_ids, :jsonb, null: false, default: []
  end
end

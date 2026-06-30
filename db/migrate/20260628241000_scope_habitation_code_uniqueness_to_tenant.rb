class ScopeHabitationCodeUniquenessToTenant < ActiveRecord::Migration[7.1]
  GLOBAL_CODIGO_INDEX = "index_habitations_on_codigo".freeze
  TENANT_CODIGO_INDEX = "index_habitations_on_tenant_id_and_codigo".freeze
  GLOBAL_DWV_INDEX = "index_habitations_on_codigo_dwv_unique_when_dwv".freeze
  TENANT_DWV_INDEX = "index_habitations_on_tenant_id_and_codigo_dwv_unique_when_dwv".freeze

  def up
    remove_index :habitations, name: GLOBAL_CODIGO_INDEX if index_exists?(:habitations, :codigo, name: GLOBAL_CODIGO_INDEX)
    add_index :habitations, [:tenant_id, :codigo], unique: true, name: TENANT_CODIGO_INDEX unless index_exists?(:habitations, [:tenant_id, :codigo], name: TENANT_CODIGO_INDEX)

    if index_exists?(:habitations, :codigo_dwv, name: GLOBAL_DWV_INDEX)
      remove_index :habitations, name: GLOBAL_DWV_INDEX
    end
    unless index_exists?(:habitations, [:tenant_id, :codigo_dwv], name: TENANT_DWV_INDEX)
      add_index :habitations,
                [:tenant_id, :codigo_dwv],
                unique: true,
                where: "imovel_dwv = 'Sim' AND codigo_dwv IS NOT NULL AND codigo_dwv <> ''",
                name: TENANT_DWV_INDEX
    end
  end

  def down
    remove_index :habitations, name: TENANT_CODIGO_INDEX if index_exists?(:habitations, [:tenant_id, :codigo], name: TENANT_CODIGO_INDEX)
    add_index :habitations, :codigo, unique: true, name: GLOBAL_CODIGO_INDEX unless index_exists?(:habitations, :codigo, name: GLOBAL_CODIGO_INDEX)

    if index_exists?(:habitations, [:tenant_id, :codigo_dwv], name: TENANT_DWV_INDEX)
      remove_index :habitations, name: TENANT_DWV_INDEX
    end
    unless index_exists?(:habitations, :codigo_dwv, name: GLOBAL_DWV_INDEX)
      add_index :habitations,
                :codigo_dwv,
                unique: true,
                where: "imovel_dwv = 'Sim' AND codigo_dwv IS NOT NULL AND codigo_dwv <> ''",
                name: GLOBAL_DWV_INDEX
    end
  end
end

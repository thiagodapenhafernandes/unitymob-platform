class AddProprietorsLowerTrimNameIndex < ActiveRecord::Migration[7.1]
  # Busca de proprietário por nome normalizado — casa com o predicado
  # lower(trim(name)) = ? usado na validação de duplicidade (proprietor.rb),
  # no Habitations::ProprietorLinker e na Vista::PropertyReconciliationService,
  # sempre com igualdade em tenant_id à frente.
  INDEX_NAME = "idx_proprietors_on_tenant_lower_trim_name".freeze

  def up
    execute <<~SQL
      CREATE INDEX IF NOT EXISTS #{INDEX_NAME}
      ON proprietors (tenant_id, lower(trim(name)))
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS #{INDEX_NAME}"
  end
end

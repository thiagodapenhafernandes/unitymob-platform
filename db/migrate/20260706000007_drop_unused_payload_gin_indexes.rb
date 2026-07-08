class DropUnusedPayloadGinIndexes < ActiveRecord::Migration[7.1]
  # habitations acumula ~212MB de índice para ~25MB de dados. Os GIN abaixo
  # cobrem colunas de payload bruto de armazenamento que NENHUMA query SQL do
  # app consulta (grep em app/ e lib/ por @>, ->>, jsonb_* etc.) e têm
  # idx_scan = 0 — só custo de escrita e disco.
  #
  # MANTIDOS de propósito (código consulta a coluna em SQL):
  # - index_habitations_on_pictures (search_scopes, habitation_intakes,
  #   Vista::ApiPictureMaterializationService);
  # - index_habitations_on_infra_estrutura (search_scopes, habitations_controller).
  DROPPED = {
    "index_habitations_on_vista_payload" => { table: :habitations, column: :vista_payload },
    "index_habitations_on_dwv_payload" => { table: :habitations, column: :dwv_payload },
    "index_vista_file_assets_on_metadata" => { table: :vista_file_assets, column: :metadata },
    "index_habitation_interactions_on_metadata" => { table: :habitation_interactions, column: :metadata }
  }.freeze

  def up
    DROPPED.each_key do |name|
      execute "DROP INDEX IF EXISTS #{name}"
    end
  end

  def down
    DROPPED.each do |name, spec|
      execute "CREATE INDEX IF NOT EXISTS #{name} ON #{spec[:table]} USING gin (#{spec[:column]})"
    end
  end
end

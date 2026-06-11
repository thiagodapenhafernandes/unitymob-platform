class AddUniqueIndexToHabitationsDwvLink < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_habitations_on_codigo_dwv_unique_when_dwv".freeze

  def up
    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY codigo_dwv
                 ORDER BY
                   CASE WHEN last_sync_at IS NULL THEN 1 ELSE 0 END,
                   last_sync_at DESC,
                   updated_at DESC,
                   id DESC
               ) AS rn
        FROM habitations
        WHERE imovel_dwv = 'Sim'
          AND codigo_dwv IS NOT NULL
          AND codigo_dwv <> ''
      )
      UPDATE habitations h
      SET codigo_dwv = NULL,
          imovel_dwv = 'Não',
          last_sync_status = 'deduplicated',
          last_sync_message = 'Vínculo DWV removido por deduplicação automática em migração de índice único.',
          last_sync_at = CURRENT_TIMESTAMP,
          updated_at = CURRENT_TIMESTAMP
      FROM ranked
      WHERE h.id = ranked.id
        AND ranked.rn > 1;
    SQL

    remove_index :habitations, name: INDEX_NAME, algorithm: :concurrently, if_exists: true

    add_index :habitations,
              :codigo_dwv,
              unique: true,
              where: "imovel_dwv = 'Sim' AND codigo_dwv IS NOT NULL AND codigo_dwv <> ''",
              name: INDEX_NAME,
              algorithm: :concurrently
  end

  def down
    remove_index :habitations, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end

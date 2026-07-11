class AddSearchableFeaturesToHabitations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    execute <<~SQL
      CREATE OR REPLACE FUNCTION habitation_searchable_features(
        characteristics jsonb,
        infrastructure jsonb,
        unique_features text[],
        description text,
        orientation text
      ) RETURNS text
      LANGUAGE sql
      IMMUTABLE
      PARALLEL SAFE
      AS $$
        SELECT lower(
          coalesce(characteristics::text, '') || ' ' ||
          coalesce(infrastructure::text, '') || ' ' ||
          coalesce(array_to_string(unique_features, ' '), '') || ' ' ||
          coalesce(description, '') || ' ' ||
          coalesce(orientation, '')
        )
      $$
    SQL

    execute <<~SQL
      ALTER TABLE habitations
      ADD COLUMN IF NOT EXISTS searchable_features text
      GENERATED ALWAYS AS (
        habitation_searchable_features(
          caracteristicas,
          infra_estrutura,
          caracteristica_unica,
          descricao_web,
          face
        )
      ) STORED
    SQL

    execute <<~SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_habitations_searchable_features_trgm
      ON habitations USING gin (searchable_features gin_trgm_ops)
    SQL
  end

  def down
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_habitations_searchable_features_trgm"
    remove_column :habitations, :searchable_features, if_exists: true
    execute "DROP FUNCTION IF EXISTS habitation_searchable_features(jsonb, jsonb, text[], text, text)"
  end
end

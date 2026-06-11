class BackfillImediacoesAttributeOptions < ActiveRecord::Migration[7.1]
  def up
    # 1) Prefer canonical source from addresses.imediacoes (text[])
    execute <<~SQL
      INSERT INTO attribute_options (name, category, context, created_at, updated_at)
      SELECT canonical_item, 'imediacoes', 'habitation', NOW(), NOW()
      FROM (
        SELECT MIN(item) AS canonical_item, lower(item) AS normalized_item
        FROM (
          SELECT btrim(regexp_replace(value, '\\s+', ' ', 'g')) AS item
          FROM addresses
          CROSS JOIN LATERAL unnest(COALESCE(addresses.imediacoes, '{}'::text[])) AS value
          WHERE addresses.addressable_type = 'Habitation'
        ) base
        WHERE item <> ''
        GROUP BY lower(item)
      ) normalized
      WHERE canonical_item <> ''
        AND NOT EXISTS (
          SELECT 1
          FROM attribute_options ao
          WHERE ao.category = 'imediacoes'
            AND ao.context = 'habitation'
            AND lower(ao.name) = normalized.normalized_item
        );
    SQL

    # 2) Fallback from legacy habitations.imediacoes (text) for records not represented in addresses yet
    execute <<~SQL
      INSERT INTO attribute_options (name, category, context, created_at, updated_at)
      SELECT canonical_item, 'imediacoes', 'habitation', NOW(), NOW()
      FROM (
        SELECT MIN(item) AS canonical_item, lower(item) AS normalized_item
        FROM (
          SELECT btrim(regexp_replace(value, '\\s+', ' ', 'g')) AS item
          FROM habitations
          CROSS JOIN LATERAL unnest(regexp_split_to_array(COALESCE(habitations.imediacoes, ''), E'[,;\\n\\r]+')) AS value
        ) base
        WHERE item <> ''
        GROUP BY lower(item)
      ) normalized
      WHERE canonical_item <> ''
        AND NOT EXISTS (
          SELECT 1
          FROM attribute_options ao
          WHERE ao.category = 'imediacoes'
            AND ao.context = 'habitation'
            AND lower(ao.name) = normalized.normalized_item
        );
    SQL
  end

  def down
    # Data backfill is intentionally irreversible.
  end
end

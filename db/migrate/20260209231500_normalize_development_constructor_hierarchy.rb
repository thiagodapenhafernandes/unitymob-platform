class NormalizeDevelopmentConstructorHierarchy < ActiveRecord::Migration[7.1]
  def up
    # 1) Populate constructor_id on developments from legacy text when possible.
    execute <<~SQL
      WITH constructor_match AS (
        SELECT h.id AS habitation_id,
               MIN(c.id) AS constructor_id
        FROM habitations h
        JOIN constructors c
          ON lower(unaccent(c.name)) = lower(unaccent(h.construtora))
        WHERE h.tipo = 'Empreendimento'
          AND h.constructor_id IS NULL
          AND NULLIF(btrim(h.construtora), '') IS NOT NULL
        GROUP BY h.id
      )
      UPDATE habitations h
      SET constructor_id = cm.constructor_id,
          updated_at = NOW()
      FROM constructor_match cm
      WHERE h.id = cm.habitation_id;
    SQL

    # 2) Normalize legacy text from constructor_id to keep backward compatibility.
    execute <<~SQL
      UPDATE habitations h
      SET construtora = c.name,
          updated_at = NOW()
      FROM constructors c
      WHERE h.constructor_id = c.id
        AND COALESCE(h.construtora, '') <> c.name;
    SQL

    # 3) Try fixing orphan unit links by exact development name when unique.
    execute <<~SQL
      WITH orphan_units AS (
        SELECT u.id,
               u.nome_empreendimento
        FROM habitations u
        WHERE NULLIF(btrim(u.codigo_empreendimento), '') IS NOT NULL
          AND NOT EXISTS (
            SELECT 1
            FROM habitations d
            WHERE d.tipo = 'Empreendimento'
              AND d.codigo = u.codigo_empreendimento
          )
          AND NULLIF(btrim(u.nome_empreendimento), '') IS NOT NULL
      ),
      unique_dev AS (
        SELECT lower(unaccent(nome_empreendimento)) AS normalized_name,
               MIN(codigo) AS codigo,
               COUNT(*) AS total
        FROM habitations
        WHERE tipo = 'Empreendimento'
          AND NULLIF(btrim(codigo), '') IS NOT NULL
          AND NULLIF(btrim(nome_empreendimento), '') IS NOT NULL
        GROUP BY lower(unaccent(nome_empreendimento))
        HAVING COUNT(*) = 1
      )
      UPDATE habitations u
      SET codigo_empreendimento = ud.codigo,
          updated_at = NOW()
      FROM orphan_units ou
      JOIN unique_dev ud
        ON lower(unaccent(ou.nome_empreendimento)) = ud.normalized_name
      WHERE u.id = ou.id;
    SQL

    # 4) Remove invalid parent codes that still do not map to any development.
    execute <<~SQL
      UPDATE habitations u
      SET codigo_empreendimento = NULL,
          updated_at = NOW()
      WHERE NULLIF(btrim(u.codigo_empreendimento), '') IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM habitations d
          WHERE d.tipo = 'Empreendimento'
            AND d.codigo = u.codigo_empreendimento
        );
    SQL

    # 5) Propagate canonical parent data to units (development name + constructor).
    execute <<~SQL
      UPDATE habitations u
      SET nome_empreendimento = COALESCE(d.nome_empreendimento, d.titulo_anuncio),
          constructor_id = d.constructor_id,
          construtora = c.name,
          updated_at = NOW()
      FROM habitations d
      LEFT JOIN constructors c ON c.id = d.constructor_id
      WHERE d.tipo = 'Empreendimento'
        AND u.codigo_empreendimento = d.codigo
        AND (
          COALESCE(u.nome_empreendimento, '') <> COALESCE(d.nome_empreendimento, d.titulo_anuncio, '')
          OR COALESCE(u.constructor_id, -1) <> COALESCE(d.constructor_id, -1)
          OR COALESCE(u.construtora, '') <> COALESCE(c.name, '')
        );
    SQL
  end

  def down
    # Irreversible cleanup/sync migration.
  end
end

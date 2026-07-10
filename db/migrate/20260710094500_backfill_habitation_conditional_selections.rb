class BackfillHabitationConditionalSelections < ActiveRecord::Migration[7.1]
  MIGRATION_KEY = "20260710094500_backfill_habitation_conditional_selections".freeze

  def up
    backfill(
      field: "aceita_parcelamento_flag",
      value_sql: "TRUE",
      condition: "aceita_parcelamento_flag = FALSE AND numero_prestacoes > 0"
    )
    backfill(
      field: "home_corporate_flag",
      value_sql: "TRUE",
      condition: "home_corporate_flag = FALSE AND home_corporate_position IS NOT NULL"
    )
    backfill(
      field: "key_location",
      value_sql: connection.quote("Zelador"),
      value_json_sql: "to_jsonb(#{connection.quote("Zelador")}::text)",
      condition: <<~SQL.squish
        NULLIF(TRIM(key_location), '') IS NULL
        AND (NULLIF(TRIM(zelador_nome), '') IS NOT NULL OR NULLIF(TRIM(zelador_telefone), '') IS NOT NULL)
      SQL
    )
    backfill(
      field: "key_location",
      value_sql: connection.quote("Outro"),
      value_json_sql: "to_jsonb(#{connection.quote("Outro")}::text)",
      condition: <<~SQL.squish
        NULLIF(TRIM(key_location), '') IS NULL
        AND NULLIF(TRIM(key_location_notes), '') IS NOT NULL
        AND NULLIF(TRIM(zelador_nome), '') IS NULL
        AND NULLIF(TRIM(zelador_telefone), '') IS NULL
      SQL
    )
  end

  def down
    restore("key_location")
    restore("home_corporate_flag", boolean: true)
    restore("aceita_parcelamento_flag", boolean: true)
  end

  private

  def backfill(field:, value_sql:, condition:, value_json_sql: "to_jsonb(#{value_sql})")
    quoted_field = connection.quote(field)
    quoted_key = connection.quote(MIGRATION_KEY)

    execute <<~SQL
      INSERT INTO habitation_audit_logs
        (habitation_id, action, source, changed_fields, changeset, metadata, created_at, tenant_id)
      SELECT
        id,
        'updated',
        'sistema',
        ARRAY[#{quoted_field}]::text[],
        jsonb_build_object(
          #{quoted_field},
          jsonb_build_object('before', to_jsonb(#{field}), 'after', #{value_json_sql})
        ),
        jsonb_build_object('data_migration', #{quoted_key}),
        CURRENT_TIMESTAMP,
        tenant_id
      FROM habitations
      WHERE #{condition}
    SQL

    execute <<~SQL
      UPDATE habitations
      SET #{field} = #{value_sql}
      WHERE #{condition}
    SQL
  end

  def restore(field, boolean: false)
    source_logs = <<~SQL.squish
      SELECT DISTINCT ON (habitation_id)
        habitation_id, changeset
      FROM habitation_audit_logs
      WHERE metadata ->> 'data_migration' = #{connection.quote(MIGRATION_KEY)}
        AND changed_fields = ARRAY[#{connection.quote(field)}]::text[]
      ORDER BY habitation_id, created_at DESC, id DESC
    SQL
    restored_value = if boolean
      "(logs.changeset #>> '{#{field},before}')::boolean"
    else
      "logs.changeset #>> '{#{field},before}'"
    end

    execute <<~SQL
      INSERT INTO habitation_audit_logs
        (habitation_id, action, source, changed_fields, changeset, metadata, created_at, tenant_id)
      SELECT
        habitations.id,
        'updated',
        'sistema',
        ARRAY[#{connection.quote(field)}]::text[],
        jsonb_build_object(
          #{connection.quote(field)},
          jsonb_build_object(
            'before', to_jsonb(habitations.#{field}),
            'after', logs.changeset #> '{#{field},before}'
          )
        ),
        jsonb_build_object('data_migration_rollback', #{connection.quote(MIGRATION_KEY)}),
        CURRENT_TIMESTAMP,
        habitations.tenant_id
      FROM habitations AS habitations
      INNER JOIN (#{source_logs}) AS logs ON logs.habitation_id = habitations.id
    SQL

    execute <<~SQL
      UPDATE habitations AS habitations
      SET #{field} = #{restored_value}
      FROM (#{source_logs}) AS logs
      WHERE logs.habitation_id = habitations.id
    SQL
  end
end

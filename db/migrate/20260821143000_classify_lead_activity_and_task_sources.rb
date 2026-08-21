class ClassifyLeadActivityAndTaskSources < ActiveRecord::Migration[7.1]
  EXTERNAL_ACTIVITY_KINDS = %w[
    external_lead_imported
    external_lead_synced
    external_first_message
    external_message
    external_log
    external_scheduled_action
    external_appointment
    c2s_imported
  ].freeze

  AUTOMATION_ACTIVITY_KINDS = %w[
    automation
    automation_event
    automation_redistribution
    automation_available
  ].freeze

  AUTOMATION_BY_VALUES = [
    "Automação",
    "Automação da etapa",
    "Inteligência de Interesse"
  ].freeze

  def up
    add_column :lead_activities, :source_category, :string, null: false, default: "human"
    add_column :tasks, :source, :string, null: false, default: "manual"

    add_index :lead_activities, [:source_category, :kind, :created_at], name: "idx_lead_activities_on_source_kind_created"
    add_index :tasks, [:tenant_id, :source, :status, :due_at], name: "idx_tasks_on_tenant_source_status_due_at"

    backfill_lead_activity_sources
    backfill_task_sources
  end

  def down
    remove_index :tasks, name: "idx_tasks_on_tenant_source_status_due_at", if_exists: true
    remove_index :lead_activities, name: "idx_lead_activities_on_source_kind_created", if_exists: true

    remove_column :tasks, :source, if_exists: true
    remove_column :lead_activities, :source_category, if_exists: true
  end

  private

  def backfill_lead_activity_sources
    execute <<~SQL.squish
      UPDATE lead_activities
         SET source_category = 'external_sync'
       WHERE kind IN (#{quoted_list(EXTERNAL_ACTIVITY_KINDS)})
    SQL

    execute <<~SQL.squish
      UPDATE lead_activities
         SET source_category = 'automation'
       WHERE kind IN (#{quoted_list(AUTOMATION_ACTIVITY_KINDS)})
          OR metadata ->> 'by' IN (#{quoted_list(AUTOMATION_BY_VALUES)})
          OR metadata ? 'automation_id'
          OR metadata ? 'lead_pipeline_stage_automation_id'
    SQL
  end

  def backfill_task_sources
    execute <<~SQL.squish
      UPDATE tasks
         SET source = 'external_legacy'
       WHERE title = 'Ação agendada do legado'
          OR id IN (
               SELECT (metadata ->> 'task_id')::bigint
                 FROM lead_activities
                WHERE kind = 'external_scheduled_action'
                  AND metadata ? 'task_id'
                  AND metadata ->> 'task_id' ~ '^[0-9]+$'
             )
    SQL

    execute <<~SQL.squish
      UPDATE tasks
         SET source = 'automation'
       WHERE source = 'manual'
         AND id IN (
               SELECT (metadata ->> 'task_id')::bigint
                 FROM lead_activities
                WHERE kind = 'task_created'
                  AND metadata ? 'task_id'
                  AND metadata ->> 'task_id' ~ '^[0-9]+$'
                  AND (
                    metadata ->> 'by' IN (#{quoted_list(AUTOMATION_BY_VALUES)})
                    OR metadata ? 'automation_id'
                    OR metadata ? 'lead_pipeline_stage_automation_id'
                  )
             )
    SQL
  end

  def quoted_list(values)
    values.map { |value| connection.quote(value) }.join(", ")
  end
end

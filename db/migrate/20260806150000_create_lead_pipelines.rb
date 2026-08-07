class CreateLeadPipelines < ActiveRecord::Migration[7.1]
  LEGACY_STATUSES = ["Novo", "Em Atendimento", "Aguardando Aceite", "Represado", "Descartado", "Concluido"].freeze

  class MigrationTenant < ActiveRecord::Base
    self.table_name = "tenants"
  end

  class MigrationAttributeOption < ActiveRecord::Base
    self.table_name = "attribute_options"
  end

  class MigrationLeadPipeline < ActiveRecord::Base
    self.table_name = "lead_pipelines"
  end

  class MigrationLeadPipelineStage < ActiveRecord::Base
    self.table_name = "lead_pipeline_stages"
  end

  class MigrationLead < ActiveRecord::Base
    self.table_name = "leads"
  end

  def change
    create_table :lead_pipelines do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "custom"
      t.boolean :active, null: false, default: true
      t.boolean :default_for_sale, null: false, default: false
      t.boolean :default_for_rental, null: false, default: false
      t.boolean :default_general, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :lead_pipelines, [:tenant_id, :name], unique: true
    add_index :lead_pipelines, [:tenant_id, :kind]
    add_index :lead_pipelines, [:tenant_id, :active, :position]

    create_table :lead_pipeline_stages do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead_pipeline, null: false, foreign_key: true
      t.string :name, null: false
      t.string :stage_type, null: false, default: "open"
      t.string :color
      t.string :description
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :lead_pipeline_stages, [:tenant_id, :lead_pipeline_id, :name], unique: true, name: "index_pipeline_stages_on_tenant_pipeline_name"
    add_index :lead_pipeline_stages, [:tenant_id, :lead_pipeline_id, :position], name: "index_pipeline_stages_on_tenant_pipeline_position"
    add_index :lead_pipeline_stages, [:tenant_id, :stage_type]

    add_reference :leads, :lead_pipeline, foreign_key: true
    add_reference :leads, :lead_pipeline_stage, foreign_key: true
    add_index :leads, [:tenant_id, :lead_pipeline_id, :lead_pipeline_stage_id], name: "index_leads_on_tenant_pipeline_stage"

    reversible do |dir|
      dir.up { backfill_default_pipelines! }
    end
  end

  private

  def backfill_default_pipelines!
    reset_column_information!

    MigrationTenant.find_each do |tenant|
      pipeline = MigrationLeadPipeline.create!(
        tenant_id: tenant.id,
        name: "Principal",
        kind: "mixed",
        active: true,
        default_for_sale: true,
        default_for_rental: true,
        default_general: true,
        position: 0,
        created_at: Time.current,
        updated_at: Time.current
      )

      status_rows = MigrationAttributeOption
        .where(tenant_id: tenant.id, context: "lead", category: "status")
        .order(Arel.sql("position ASC NULLS LAST"), :name)
        .pluck(:name, :description)
        .select { |name, _description| name.to_s.strip.present? }
        .uniq { |name, _description| normalized_key(name) }

      status_rows = LEGACY_STATUSES.map { |name| [name, nil] } if status_rows.blank?

      stages_by_name = {}
      status_rows.each_with_index do |(name, description), index|
        stage = MigrationLeadPipelineStage.create!(
          tenant_id: tenant.id,
          lead_pipeline_id: pipeline.id,
          name: name,
          description: description,
          stage_type: stage_type_for(name),
          active: true,
          position: index,
          created_at: Time.current,
          updated_at: Time.current
        )
        stages_by_name[normalized_key(name)] = stage
      end

      default_stage = stages_by_name[normalized_key("Novo")] || stages_by_name.values.first

      MigrationLead.where(tenant_id: tenant.id).find_each do |lead|
        stage = stages_by_name[normalized_key(lead.status)] || default_stage
        lead.update_columns(
          lead_pipeline_id: pipeline.id,
          lead_pipeline_stage_id: stage&.id,
          status: stage&.name || lead.status,
          updated_at: lead.updated_at
        )
      end
    end
  end

  def reset_column_information!
    [MigrationTenant, MigrationAttributeOption, MigrationLeadPipeline, MigrationLeadPipelineStage, MigrationLead].each(&:reset_column_information)
  end

  def stage_type_for(name)
    key = normalized_key(name)
    return "won" if key.include?("concluido") || key.include?("vendido") || key.include?("locado") || key.include?("fechado")
    return "lost" if key.include?("descartado") || key.include?("perdido")
    return "archived" if key.include?("arquivado")

    "open"
  end

  def normalized_key(value)
    value.to_s.parameterize(separator: "_")
  end
end

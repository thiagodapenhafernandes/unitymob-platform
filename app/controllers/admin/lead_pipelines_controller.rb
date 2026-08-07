module Admin
  class LeadPipelinesController < Admin::BaseController
    before_action -> { check_permission!(:manage, :catalogos) }
    before_action :load_pipeline, only: [:update]

    def create
      pipeline = current_tenant.lead_pipelines.new(pipeline_params)
      stages = stage_rows_params

      LeadPipeline.transaction do
        apply_defaults_from_kind!(pipeline)
        clear_defaults!(pipeline)
        pipeline.save!
        create_initial_stages!(pipeline, stages)
        ensure_initial_stage!(pipeline)
      end

      redirect_to admin_lead_pipeline_leads_path(pipeline, view: view_mode), notice: "Funil criado."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_leads_path(view: view_mode), alert: e.record.errors.full_messages.to_sentence
    end

    def update
      @pipeline.assign_attributes(pipeline_params)

      LeadPipeline.transaction do
        apply_defaults_from_kind!(@pipeline)
        clear_defaults!(@pipeline)
        @pipeline.save!
      end

      redirect_to admin_lead_pipeline_leads_path(@pipeline, view: view_mode), notice: "Funil atualizado."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_leads_path(lead_pipeline_id: @pipeline&.id, view: view_mode), alert: e.record.errors.full_messages.to_sentence
    end

    private

    def load_pipeline
      @pipeline = current_tenant.lead_pipelines.find(params[:id])
    end

    def pipeline_params
      params.require(:lead_pipeline).permit(:name, :kind, :active)
    end

    def stage_rows_params
      raw_rows = params[:stages]
      rows = case raw_rows
      when ActionController::Parameters
        raw_rows.to_unsafe_h.values
      when Hash
        raw_rows.values
      else
        Array(raw_rows)
      end

      rows.filter_map do |row|
        next unless row.respond_to?(:to_h)

        permitted = ActionController::Parameters.new(row.to_h).permit(:name, :description, :stage_type)
        name = permitted[:name].to_s.strip
        next if name.blank?

        {
          name: name,
          description: permitted[:description].to_s.strip,
          stage_type: permitted[:stage_type].presence_in(LeadPipelineStage::STAGE_TYPES.keys) || "open"
        }
      end
    end

    def clear_defaults!(pipeline)
      {
        default_general: pipeline.default_general?,
        default_for_sale: pipeline.default_for_sale?,
        default_for_rental: pipeline.default_for_rental?
      }.each do |attribute, enabled|
        next unless enabled

        current_tenant.lead_pipelines.where(attribute => true).where.not(id: pipeline.id).update_all(attribute => false, updated_at: Time.current)
      end
    end

    def apply_defaults_from_kind!(pipeline)
      pipeline.default_general = false
      pipeline.default_for_sale = false
      pipeline.default_for_rental = false

      case pipeline.kind.to_s
      when "sale"
        pipeline.default_for_sale = true
      when "rental"
        pipeline.default_for_rental = true
      when "mixed"
        pipeline.default_general = true
        pipeline.default_for_sale = true
        pipeline.default_for_rental = true
      end
    end

    def ensure_initial_stage!(pipeline)
      return if pipeline.stages.exists?

      current_tenant.lead_pipeline_stages.create!(lead_pipeline: pipeline, name: Lead::DEFAULT_STATUS, position: 0)
    end

    def create_initial_stages!(pipeline, stages)
      stages.each_with_index do |stage, index|
        current_tenant.lead_pipeline_stages.create!(
          lead_pipeline: pipeline,
          name: stage[:name],
          description: stage[:description],
          stage_type: stage[:stage_type],
          position: index
        )
      end
    end

    def view_mode
      params[:view].presence_in(%w[kanban list]) || "kanban"
    end
  end
end

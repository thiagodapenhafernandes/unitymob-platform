module Admin
  # Gerencia as etapas do funil de leads selecionado.
  class LeadStatusesController < Admin::BaseController
    before_action -> { check_permission!(:manage, :catalogos) }

    def index
      render json: stages_scope.map { |stage|
        { id: stage.id, name: stage.name, description: stage.description, stage_type: stage.stage_type }
      }
    end

    def bulk_update
      rows = params.permit(:lead_pipeline_id, statuses: [:id, :name, :description, :stage_type, :_destroy]).fetch(:statuses, [])

      LeadPipelineStage.transaction do
        rows.each_with_index do |row, index|
          apply_row(row, index)
        end
      end

      flash[:notice] = "Etapas do funil atualizadas."
      render json: { ok: true }
    rescue ActiveRecord::RecordInvalid => e
      message = e.record&.errors&.full_messages&.to_sentence
      render json: { ok: false, error: message.presence || e.message }, status: :unprocessable_entity
    end

    private

    def apply_row(row, index)
      id = row[:id].presence
      name = row[:name].to_s.strip
      description = row[:description].to_s.strip
      stage_type = row[:stage_type].presence_in(LeadPipelineStage::STAGE_TYPES.keys) || "open"
      destroy = ActiveModel::Type::Boolean.new.cast(row[:_destroy])

      if id.present?
        stage = selected_pipeline.stages.find_by(id: id)
        return if stage.nil?

        if destroy
          fallback_stage = selected_pipeline.stages.where.not(id: stage.id).ordered.first
          current_tenant.leads.where(lead_pipeline_stage_id: stage.id).update_all(
            lead_pipeline_stage_id: fallback_stage&.id,
            status: fallback_stage&.name || Lead.default_status(tenant: current_tenant, pipeline: selected_pipeline),
            updated_at: Time.current
          )
          stage.destroy!
        else
          stage.update!(name: name, description: description, stage_type: stage_type, position: index)
        end
      elsif !destroy && name.present?
        current_tenant.lead_pipeline_stages.create!(
          lead_pipeline: selected_pipeline,
          name: name,
          description: description,
          stage_type: stage_type,
          position: index
        )
      end
    end

    def selected_pipeline
      @selected_pipeline ||= begin
        if params[:lead_pipeline_id].present?
          current_tenant.lead_pipelines.find_by(id: params[:lead_pipeline_id]) || LeadPipeline.ensure_default!(tenant: current_tenant)
        else
          LeadPipeline.ensure_default!(tenant: current_tenant)
        end
      end
    end

    def stages_scope
      selected_pipeline.stages.ordered
    end
  end
end

module Admin
  # Gerencia as etapas do funil de leads selecionado.
  class LeadStatusesController < Admin::BaseController
    before_action -> { check_permission!(:manage, :catalogos) }

    def index
      render json: stages_scope.map { |stage|
        {
          id: stage.id,
          name: stage.name,
          description: stage.description,
          stage_type: stage.stage_type,
          automations: stage.automations.ordered.map { |automation|
            {
              id: automation.id,
              trigger: automation.trigger,
              after_amount: automation.after_amount,
              after_unit: automation.after_unit,
              auto_advance_to_stage_id: automation.auto_advance_to_stage_id,
              active: automation.active
            }
          }
        }
      }
    end

    def bulk_update
      rows = params.permit(
        :lead_pipeline_id,
        statuses: [
          :id, :name, :description, :stage_type, :_destroy,
          automations: [
            :id, :trigger, :after_amount, :after_unit, :auto_advance_to_stage_id, :active, :_destroy
          ]
        ]
      ).fetch(:statuses, [])

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
          sync_automations!(stage, row[:automations])
        end
      elsif !destroy && name.present?
        stage = current_tenant.lead_pipeline_stages.create!(
          lead_pipeline: selected_pipeline,
          name: name,
          description: description,
          stage_type: stage_type,
          position: index
        )
        sync_automations!(stage, row[:automations])
      end
    end

    def sync_automations!(stage, raw_rows)
      rows = automation_rows(raw_rows)
      retained_ids = []

      rows.each_with_index do |row, index|
        id = row[:id].presence
        destroy = ActiveModel::Type::Boolean.new.cast(row[:_destroy])
        automation = id.present? ? stage.automations.find_by(id: id) : stage.automations.build
        next if automation.blank?

        if destroy
          automation.destroy! if automation.persisted?
          next
        end

        amount = row[:after_amount].to_i
        destination = current_tenant.lead_pipeline_stages.find_by(id: row[:auto_advance_to_stage_id].presence)
        next if amount <= 0 && destination.blank?

        automation.assign_attributes(
          tenant: current_tenant,
          trigger: row[:trigger].presence_in(LeadPipelineStageAutomation::TRIGGERS.keys) || "stage_duration",
          after_amount: amount,
          after_unit: row[:after_unit].presence_in(LeadPipelineStageAutomation::UNITS.keys) || "days",
          auto_advance_to_stage: destination,
          active: ActiveModel::Type::Boolean.new.cast(row.fetch(:active, true)),
          position: index
        )
        automation.save!
        retained_ids << automation.id
      end

      stage.automations.where.not(id: retained_ids).destroy_all
    end

    def automation_rows(raw_rows)
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

        row.to_h.with_indifferent_access
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

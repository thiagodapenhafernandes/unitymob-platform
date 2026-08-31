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
          color: stage.display_color,
          active: stage.active,
          policy: policy_payload(stage.policy_or_default),
          next_stage_ids: stage.transitions.ordered.pluck(:next_stage_id),
          automations: stage.automations.ordered.map { |automation|
            {
              id: automation.id,
              trigger: automation.trigger,
              after_amount: automation.after_amount,
              after_unit: automation.after_unit,
              auto_advance_to_stage_id: automation.auto_advance_to_stage_id,
              action_type: automation.action_type,
              action_config: automation.action_config,
              active: automation.active
            }
          }
        }
      }
    end

    def documentation
      @page_title = "Guia de funis e etapas"
    end

    def automation_executions
      @page_title = "Auditoria das automações de etapas"
      @status = params[:status].to_s.presence_in(LeadPipelineStageAutomationExecution::STATUSES.keys)
      @action_type = params[:action_type].to_s.presence_in(LeadPipelineStageAutomation::ACTION_TYPES.keys)
      @stage_id = params[:lead_pipeline_stage_id].to_s.presence
      @q = params[:q].to_s.squish
      @status_counts = current_tenant.lead_pipeline_stage_automation_executions.group(:status).count
      @action_counts = current_tenant.lead_pipeline_stage_automation_executions.group(:action_type).count
      @stage_options = current_tenant.lead_pipeline_stages.active.ordered.pluck(:name, :id)
      @executions = automation_execution_scope.paginate(page: params[:page], per_page: 30)
    end

    def bulk_update
      rows = params.permit(
        :lead_pipeline_id,
        statuses: [
          :id, :name, :description, :stage_type, :color, :active, :_destroy,
          automations: [
            :id, :trigger, :after_amount, :after_unit, :auto_advance_to_stage_id, :action_type, :active, :_destroy,
            action_config: {}
          ],
          policy: [
            :divergence_queue_enabled, :future_activity_limit_days, :qualification_enabled,
            visible_to_roles: [],
            qualification_options: [],
            allowed_archive_reason_ids: []
          ],
          next_stage_ids: []
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

    def automation_execution_scope
      scope = current_tenant.lead_pipeline_stage_automation_executions
        .includes(:lead, :lead_pipeline_stage, lead_pipeline_stage_automation: [:lead_pipeline_stage, :auto_advance_to_stage])
        .recent
      scope = scope.where(status: @status) if @status.present?
      scope = scope.where(action_type: @action_type) if @action_type.present?
      scope = scope.where(lead_pipeline_stage_id: @stage_id) if @stage_id.present?
      if @q.present?
        query = "%#{ActiveRecord::Base.sanitize_sql_like(@q)}%"
        scope = scope.left_joins(:lead).where(
          "leads.name ILIKE :query OR leads.email ILIKE :query OR leads.phone ILIKE :query OR CAST(leads.id AS TEXT) = :id",
          query: query,
          id: @q
        )
      end
      scope
    end

    def apply_row(row, index)
      id = row[:id].presence
      name = row[:name].to_s.strip
      description = row[:description].to_s.strip
      stage_type = row[:stage_type].presence_in(LeadPipelineStage::STAGE_TYPES.keys) || "open"
      color = row[:color].to_s.strip.presence
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
          stage.update!(name: name, description: description, stage_type: stage_type, color: color, active: row.key?(:active) ? ActiveModel::Type::Boolean.new.cast(row[:active]) : true, position: index)
          sync_policy!(stage, row[:policy])
          sync_transitions!(stage, row[:next_stage_ids])
          sync_automations!(stage, row[:automations])
        end
      elsif !destroy && name.present?
        stage = current_tenant.lead_pipeline_stages.create!(
          lead_pipeline: selected_pipeline,
          name: name,
          description: description,
          stage_type: stage_type,
          color: color,
          active: row.key?(:active) ? ActiveModel::Type::Boolean.new.cast(row[:active]) : true,
          position: index
        )
        sync_policy!(stage, row[:policy])
        sync_transitions!(stage, row[:next_stage_ids])
        sync_automations!(stage, row[:automations])
      end
    end

    def sync_policy!(stage, raw_policy)
      policy_params = policy_row(raw_policy)
      policy = stage.policy || stage.build_policy(tenant: current_tenant)
      policy.assign_attributes(
        tenant: current_tenant,
        visible_to_roles: Array(policy_params[:visible_to_roles]).presence || LeadPipelineStagePolicy::DEFAULT_VISIBLE_ROLES,
        divergence_queue_enabled: ActiveModel::Type::Boolean.new.cast(policy_params.fetch(:divergence_queue_enabled, false)),
        future_activity_limit_days: policy_params[:future_activity_limit_days].presence,
        qualification_enabled: ActiveModel::Type::Boolean.new.cast(policy_params.fetch(:qualification_enabled, false)),
        qualification_options: Array(policy_params[:qualification_options]).presence || LeadPipelineStagePolicy::DEFAULT_QUALIFICATION_OPTIONS,
        allowed_archive_reason_ids: Array(policy_params[:allowed_archive_reason_ids])
      )
      policy.save!
    end

    def sync_transitions!(stage, raw_ids)
      ids = Array(raw_ids).filter_map { |id| id.to_s.presence }.uniq
      valid_ids = current_tenant.lead_pipeline_stages.where(id: ids).where.not(id: stage.id).pluck(:id)
      retained_ids = []

      valid_ids.each_with_index do |next_stage_id, index|
        transition = stage.transitions.find_or_initialize_by(next_stage_id: next_stage_id)
        transition.assign_attributes(tenant: current_tenant, position: index)
        transition.save!
        retained_ids << transition.id
      end

      stage.transitions.where.not(id: retained_ids).destroy_all
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
        action_type = row[:action_type].presence_in(LeadPipelineStageAutomation::ACTION_TYPES.keys) || "move_stage"
        destination = current_tenant.lead_pipeline_stages.find_by(id: row[:auto_advance_to_stage_id].presence)
        next if amount <= 0 && destination.blank? && action_type == "move_stage"
        next if amount <= 0 && action_type != "move_stage"

        automation.assign_attributes(
          tenant: current_tenant,
          trigger: row[:trigger].presence_in(LeadPipelineStageAutomation::TRIGGERS.keys) || "stage_duration",
          after_amount: amount,
          after_unit: row[:after_unit].presence_in(LeadPipelineStageAutomation::UNITS.keys) || "days",
          action_type: action_type,
          action_config: automation_action_config(row[:action_config], action_type),
          auto_advance_to_stage: destination,
          active: ActiveModel::Type::Boolean.new.cast(row.fetch(:active, true)),
          position: index
        )
        automation.save!
        retained_ids << automation.id
      end

      stage.automations.where.not(id: retained_ids).destroy_all
    end

    def automation_action_config(raw_config, action_type)
      config = raw_config.respond_to?(:to_h) ? raw_config.to_h.with_indifferent_access : {}
      base = {
        unsuccessful_attempt_limit: config[:unsuccessful_attempt_limit].to_i.positive? ? config[:unsuccessful_attempt_limit].to_i : nil
      }.compact

      base.merge(case action_type
      when "archive_lead"
        { archive_reason_id: config[:archive_reason_id].to_s.presence, note: config[:note].to_s.strip.presence }.compact
      when "redistribute_lead"
        { distribution_rule_id: config[:distribution_rule_id].to_s.presence, note: config[:note].to_s.strip.presence }.compact
      when "create_task"
        {
          task_title: config[:task_title].to_s.strip.presence,
          due_in_days: config[:due_in_days].to_i.positive? ? config[:due_in_days].to_i : nil,
          note: config[:note].to_s.strip.presence
        }.compact
      when "add_note", "make_available_for_automation"
        { note: config[:note].to_s.strip.presence }.compact
      else
        {}
      end)
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

    def policy_row(raw_policy)
      raw_policy.respond_to?(:to_h) ? raw_policy.to_h.with_indifferent_access : {}
    end

    def policy_payload(policy)
      {
        visible_to_roles: policy.visible_to_roles,
        divergence_queue_enabled: policy.divergence_queue_enabled,
        future_activity_limit_days: policy.future_activity_limit_days,
        qualification_enabled: policy.qualification_enabled,
        qualification_options: policy.qualification_options,
        allowed_archive_reason_ids: policy.allowed_archive_reason_ids
      }
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

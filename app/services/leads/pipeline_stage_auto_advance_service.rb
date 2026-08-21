module Leads
  class PipelineStageAutoAdvanceService
    BATCH_LIMIT = 200
    CUSTOMER_ACTIVITY_KINDS = %w[
      whatsapp_in proposal_viewed proposal_aceita proposal_recusada
    ].freeze
    TEAM_ACTIVITY_KINDS = %w[
      comment note task_created task_completed appointment_created appointment_done
      proposal_created proposal_sent whatsapp_out status_change
    ].freeze
    GENERAL_ACTIVITY_KINDS = (CUSTOMER_ACTIVITY_KINDS + TEAM_ACTIVITY_KINDS).uniq.freeze

    def self.call(limit: BATCH_LIMIT, tenant: nil)
      new(limit: limit, tenant: tenant).call
    end

    def initialize(limit:, tenant: nil)
      @limit = limit
      @tenant = tenant
    end

    def call
      automation_scope.find_each do |automation|
        Current.set(tenant: automation.tenant) do
          advance_stage(automation)
        end
      end
    end

    private

    attr_reader :limit, :tenant

    def automation_scope
      scope = LeadPipelineStageAutomation.active.includes(:tenant, :lead_pipeline_stage, :auto_advance_to_stage)
      tenant.present? ? scope.where(tenant: tenant) : scope
    end

    def advance_stage(automation)
      stage = automation.lead_pipeline_stage
      duration = automation.duration
      return if duration.blank?

      cutoff = Time.current - duration
      stage.leads.where(tenant: stage.tenant, lead_pipeline: stage.lead_pipeline, lead_pipeline_stage: stage)
        .limit(limit)
        .find_each do |lead|
          entered_at = stage_entered_at(lead) || lead.created_at
          next unless due?(lead, automation, cutoff, entered_at)

          execute_once!(lead, automation: automation, from_stage: stage, stage_entered_at: entered_at)
        end
    end

    def due?(lead, automation, cutoff, since)
      return false if since.blank?

      case automation.trigger
      when "general_inactivity"
        last_activity_at(lead, since, GENERAL_ACTIVITY_KINDS).to_i <= cutoff.to_i
      when "customer_inactivity"
        last_activity_at(lead, since, CUSTOMER_ACTIVITY_KINDS).to_i <= cutoff.to_i
      when "team_inactivity"
        last_activity_at(lead, since, TEAM_ACTIVITY_KINDS).to_i <= cutoff.to_i
      else
        since <= cutoff
      end
    end

    def stage_entered_at(lead)
      lead.lead_audit_logs
        .where(action: "status_changed")
        .order(created_at: :desc)
        .limit(1)
        .pick(:created_at) || lead.created_at
    end

    def last_activity_at(lead, fallback, kinds)
      lead.activities
        .where(kind: kinds)
        .where("created_at >= ?", fallback)
        .maximum(:created_at) || fallback
    end

    def execute_once!(lead, automation:, from_stage:, stage_entered_at:)
      execution = begin_execution!(lead, automation: automation, from_stage: from_stage, stage_entered_at: stage_entered_at)
      return if execution.blank?

      execute_action!(lead, automation: automation, from_stage: from_stage)
      execution.succeeded!
    rescue ActiveRecord::RecordNotUnique
      nil
    rescue ActiveRecord::RecordInvalid => e
      execution&.failed!(e)
      Rails.logger.warn("[lead stage automation] lead=#{lead.id} stage=#{from_stage.id} automation=#{automation.id} #{e.class}: #{e.message}")
    rescue StandardError => e
      execution&.failed!(e)
      Rails.logger.error("[lead stage automation] lead=#{lead.id} stage=#{from_stage.id} automation=#{automation.id} #{e.class}: #{e.message}")
    end

    def begin_execution!(lead, automation:, from_stage:, stage_entered_at:)
      LeadPipelineStageAutomationExecution.create!(
        tenant: automation.tenant,
        lead_pipeline_stage_automation: automation,
        lead: lead,
        lead_pipeline_stage: from_stage,
        action_type: automation.action_type,
        trigger: automation.trigger,
        status: "started",
        stage_entered_at: stage_entered_at,
        started_at: Time.current,
        metadata: automation_metadata(automation).merge(
          from_stage_id: from_stage.id,
          lead_pipeline_id: lead.lead_pipeline_id
        )
      )
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors.added?(:lead_pipeline_stage_automation_id, :taken)

      nil
    end

    def execute_action!(lead, automation:, from_stage:)
      case automation.action_type
      when "move_stage"
        move_lead!(lead, automation: automation, from_stage: from_stage, to_stage: automation.auto_advance_to_stage)
      when "archive_lead"
        archive_lead!(lead, automation: automation, from_stage: from_stage)
      when "redistribute_lead"
        redistribute_lead!(lead, automation: automation)
      when "make_available_for_automation"
        make_available_for_automation!(lead, automation: automation)
      when "create_task"
        create_task!(lead, automation: automation)
      when "add_note"
        add_note!(lead, automation: automation)
      end
    end

    def move_lead!(lead, automation:, from_stage:, to_stage:)
      return if to_stage.blank?

      from_status = lead.status
      lead.update!(lead_pipeline_stage: to_stage, status: to_stage.name)
      LeadActivity.log!(
        lead: lead,
        kind: "status_change",
        metadata: {
          from: from_status,
          to: lead.status,
          from_stage_id: from_stage.id,
          to_stage_id: to_stage.id,
          stage_automation_id: automation.id,
          trigger: automation.trigger,
          amount: automation.after_amount,
          unit: automation.after_unit,
          by: "Automação da etapa"
        }
      )
    end

    def archive_lead!(lead, automation:, from_stage:)
      policy = from_stage.policy
      reason = archive_reason_for(lead, automation, policy)
      archived_stage = archived_stage_for(lead)
      lead.assign_attributes(
        lead_pipeline_stage: archived_stage || lead.lead_pipeline_stage,
        status: archived_stage&.name || Lead.status_value(:descartado, tenant: lead.tenant),
        archive_reason: reason,
        archive_note: action_config(automation, "note").presence || "Arquivado automaticamente pela etapa #{from_stage.name}.",
        archived_at: Time.current,
        archived_by_admin_user: nil
      )
      lead.save!
      LeadActivity.log!(
        lead: lead,
        kind: "archived",
        metadata: automation_metadata(automation).merge(
          reason: reason&.name,
          note: lead.archive_note,
          from_stage_id: from_stage.id,
          by: "Automação da etapa"
        )
      )
    end

    def redistribute_lead!(lead, automation:)
      rule = distribution_rule_for(lead, automation)
      if rule
        Leads::DistributorService.distribute_to(lead, rule)
      else
        lead.update!(admin_user_id: nil, status: Lead.status_value(:waiting_acceptance, tenant: lead.tenant))
      end
      LeadActivity.log!(lead: lead, kind: "automation_redistribution", metadata: automation_metadata(automation).merge(distribution_rule_id: rule&.id))
    end

    def make_available_for_automation!(lead, automation:)
      lead.update!(admin_user_id: nil)
      LeadActivity.log!(lead: lead, kind: "automation_available", metadata: automation_metadata(automation))
    end

    def create_task!(lead, automation:)
      assignee = lead.admin_user || lead.tenant.admin_users.where(active: true).order(:id).first
      return if assignee.blank?

      task = lead.tenant.tasks.create!(
        lead: lead,
        admin_user: assignee,
        title: action_config(automation, "task_title").presence || "Follow-up automático",
        kind: "follow_up",
        due_at: (action_config(automation, "due_in_days").presence || 1).to_i.days.from_now,
        status: "pendente",
        description: action_config(automation, "note")
      )
      LeadActivity.log!(lead: lead, kind: "task_created", metadata: automation_metadata(automation).merge(task_id: task.id, title: task.title, by: "Automação da etapa"))
    end

    def add_note!(lead, automation:)
      body = action_config(automation, "note").presence || "Evento registrado automaticamente pela etapa."
      LeadActivity.log!(lead: lead, kind: "note", metadata: automation_metadata(automation).merge(contact_kind: "automação", body: body, by: "Automação da etapa"))
    end

    def action_config(automation, key)
      automation.action_config.to_h[key]
    end

    def automation_metadata(automation)
      {
        stage_automation_id: automation.id,
        trigger: automation.trigger,
        amount: automation.after_amount,
        unit: automation.after_unit,
        action_type: automation.action_type
      }
    end

    def archive_reason_for(lead, automation, policy)
      reason_id = action_config(automation, "archive_reason_id").presence ||
        Array(policy&.allowed_archive_reason_ids).first
      lead.tenant.attribute_options.for_context("lead").for_category("archive_reason").find_by(id: reason_id)
    end

    def archived_stage_for(lead)
      lead.lead_pipeline&.stages&.active&.where(stage_type: "archived")&.ordered&.first
    end

    def distribution_rule_for(lead, automation)
      rule_id = action_config(automation, "distribution_rule_id").presence || lead.distribution_rule_id
      lead.tenant.distribution_rules.active.find_by(id: rule_id)
    end
  end
end

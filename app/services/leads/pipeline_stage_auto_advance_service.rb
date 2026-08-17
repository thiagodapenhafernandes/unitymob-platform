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
      destination = automation.auto_advance_to_stage
      return if duration.blank? || destination.blank?

      cutoff = Time.current - duration
      stage.leads.where(tenant: stage.tenant, lead_pipeline: stage.lead_pipeline, lead_pipeline_stage: stage)
        .limit(limit)
        .find_each do |lead|
          next unless due?(lead, automation, cutoff)

          move_lead!(lead, automation: automation, from_stage: stage, to_stage: destination)
        end
    end

    def due?(lead, automation, cutoff)
      since = stage_entered_at(lead) || lead.created_at
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

    def move_lead!(lead, automation:, from_stage:, to_stage:)
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
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[lead stage auto advance] lead=#{lead.id} stage=#{from_stage.id} #{e.class}: #{e.message}")
    end
  end
end

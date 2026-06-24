module Admin
  # Painel do Admin do Sistema: métricas da aplicação + gestão dos próprios system admins.
  # Acima do Admin da Conta; invisível para perfis normais.
  class SystemController < BaseController
    before_action :require_system_admin!

    def index
      @metrics = system_metrics
      @system_admins = AdminUser.where(super_admin: true).includes(:profile).order(:name)
      @last_login_by_admin_id = last_login_by_admin_id(@system_admins.map(&:id))
      @failed_job_groups = failed_job_groups
    end

    private

    # Métricas de nível-aplicação. Cada bloco é defensivo (rescue) para o painel nunca
    # quebrar caso uma tabela/serviço não exista no ambiente.
    def system_metrics
      {
        admin_users:   safe_count { AdminUser.count },
        active_users:  safe_count { AdminUser.where(active: true).count },
        system_admins: safe_count { AdminUser.where(super_admin: true).count },
        profiles:      safe_count { Profile.count },
        habitations:   safe_count { Habitation.count },
        leads:         safe_count { Lead.count },
        proprietors:   safe_count { defined?(Proprietor) ? Proprietor.count : nil },
        storage_blobs: safe_count { ActiveStorage::Blob.count },
        logins_today:  safe_count { AccessAuditLog.where(event_type: "login", created_at: Time.zone.now.beginning_of_day..).count if defined?(AccessAuditLog) }
      }.merge(solid_queue_metrics)
    end

    def safe_count
      yield
    rescue StandardError
      nil
    end

    def solid_queue_metrics
      {
        jobs_unfinished: safe_count { SolidQueue::Job.where(finished_at: nil).count if defined?(SolidQueue::Job) },
        jobs_ready:      safe_count { SolidQueue::ReadyExecution.count if defined?(SolidQueue::ReadyExecution) },
        jobs_scheduled:  safe_count { SolidQueue::ScheduledExecution.count if defined?(SolidQueue::ScheduledExecution) },
        jobs_claimed:    safe_count { SolidQueue::ClaimedExecution.count if defined?(SolidQueue::ClaimedExecution) },
        jobs_blocked:    safe_count { SolidQueue::BlockedExecution.count if defined?(SolidQueue::BlockedExecution) },
        jobs_failed:     safe_count { SolidQueue::FailedExecution.count if defined?(SolidQueue::FailedExecution) },
        jobs_processes:  safe_count { SolidQueue::Process.count if defined?(SolidQueue::Process) }
      }
    end

    def last_login_by_admin_id(admin_ids)
      return {} if admin_ids.blank? || !defined?(AccessAuditLog)

      AccessAuditLog
        .where(admin_user_id: admin_ids, event_type: "login", result: "allowed")
        .group(:admin_user_id)
        .maximum(:created_at)
    rescue StandardError
      {}
    end

    def failed_job_groups
      return [] unless defined?(SolidQueue::FailedExecution)

      SolidQueue::FailedExecution
        .includes(:job)
        .order(created_at: :desc)
        .limit(1_000)
        .group_by do |execution|
          error = execution.error || {}
          [
            execution.job&.class_name.presence || "Job sem classe",
            error["exception_class"].presence || "Erro sem classe",
            error["message"].to_s.presence || error["exception_class"].to_s
          ]
        end
        .map { |(job_class, error_class, message), rows| { job_class:, error_class:, message:, count: rows.size } }
        .sort_by { |group| -group[:count] }
        .first(5)
    rescue StandardError
      []
    end
  end
end

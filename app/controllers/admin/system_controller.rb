module Admin
  # Painel do Admin do Sistema: métricas da aplicação + gestão dos próprios system admins.
  # Acima do Admin da Conta; invisível para perfis normais.
  class SystemController < BaseController
    before_action :require_system_admin!

    def index
      @metrics = system_metrics
      @system_admins = AdminUser.where(super_admin: true).order(:name)
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
        jobs_pending:  safe_count { SolidQueue::Job.where(finished_at: nil).count if defined?(SolidQueue::Job) },
        jobs_failed:   safe_count { SolidQueue::FailedExecution.count if defined?(SolidQueue::FailedExecution) },
        logins_today:  safe_count { AccessAuditLog.where(event_type: "login", created_at: Time.zone.now.beginning_of_day..).count if defined?(AccessAuditLog) }
      }
    end

    def safe_count
      yield
    rescue StandardError
      nil
    end
  end
end

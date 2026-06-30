module Admin
  # Painel do Admin do Sistema: métricas da aplicação + gestão dos próprios system admins.
  # Acima do Admin da Conta; invisível para perfis normais.
  class SystemController < BaseController
    before_action :require_system_admin!

    def index
      @metrics = system_metrics
      @tenants = Tenant.active.includes(admin_users: :profile).order(:name)
      @system_admins = AdminUser.where(super_admin: true).includes(:profile).order(:name)
      @last_login_by_admin_id = last_login_by_admin_id(@system_admins.map(&:id))
      @failed_job_groups = failed_job_groups
    end

    def users
      @query = params[:q].to_s.squish
      @tenant_id = params[:tenant_id].presence
      @status = params[:status].presence_in(%w[active inactive]) || "all"
      @user_kind = params[:user_kind].presence_in(%w[account system]) || "all"
      @profile_id = params[:profile_id].presence
      @horizontal_profile_id = params[:horizontal_profile_id].presence
      @hierarchy_user_id = params[:hierarchy_user_id].presence
      @tenants = Tenant.order(:name)
      @selected_tenant = @tenant_id.present? ? @tenants.find { |tenant| tenant.id.to_s == @tenant_id.to_s } : nil
      @account_filters_enabled = @selected_tenant.present? && @user_kind != "system"
      @tenant_vertical_profiles = @account_filters_enabled ? @selected_tenant.profiles.ordered_vertical : Profile.none
      @tenant_horizontal_profiles = @account_filters_enabled ? @selected_tenant.profiles.ordered_horizontal : Profile.none
      @hierarchy_users = @account_filters_enabled ? hierarchy_users_payload(@selected_tenant) : []
      @admin_users = system_users_scope
    end

    def impersonate_owner
      tenant = Tenant.active.find(params[:tenant_id])
      owner = tenant_owner_for(tenant)

      unless owner
        redirect_to admin_system_path, alert: "Esta conta não possui Dono da conta ativo para impersonação."
        return
      end

      start_system_impersonation!(owner, return_to: admin_system_path, reason: "Admin do Sistema iniciou impersonação pelo painel do sistema")
      redirect_to admin_root_path, notice: "Você está acessando #{tenant.name} como #{owner.name}."
    end

    def impersonate_user
      user = AdminUser.includes(:tenant, :profile, :horizontal_profile).find(params[:admin_user_id])

      if user == current_admin_user
        redirect_to admin_system_users_path, alert: "Você já está logado como este usuário."
        return
      end

      start_system_impersonation!(user, return_to: admin_system_users_path, reason: "Admin do Sistema iniciou impersonação de usuário")
      redirect_to after_system_impersonation_path(user),
                  notice: system_impersonation_notice(user)
    end

    private

    def system_users_scope
      scope = AdminUser.includes(:tenant, :profile, :horizontal_profile)
        .left_joins(:tenant)
        .order(Arel.sql("tenants.name ASC NULLS FIRST, admin_users.name ASC"))

      if @query.present?
        pattern = "%#{@query}%"
        scope = scope.where("admin_users.name ILIKE :q OR admin_users.email ILIKE :q OR tenants.name ILIKE :q", q: pattern)
      end

      if @user_kind == "system"
        scope = scope.where(super_admin: true)
      else
        scope = scope.where(super_admin: false) if @tenant_id.present? || @user_kind == "account"
        scope = scope.where(tenant_id: @tenant_id) if @tenant_id.present?
      end

      case @status
      when "active" then scope = scope.where(active: true)
      when "inactive" then scope = scope.where(active: false)
      end

      if account_filters_enabled?
        scope = scope.where(profile_id: @profile_id) if tenant_profile_filter?(@profile_id, axis: Profile::AXES[:vertical])
        scope = scope.where(horizontal_profile_id: @horizontal_profile_id) if tenant_profile_filter?(@horizontal_profile_id, axis: Profile::AXES[:horizontal])
        scope = scope.where(id: hierarchy_filter_ids) if @hierarchy_user_id.present?
      end

      scope.paginate(page: params[:page], per_page: 50)
    end

    def account_filters_enabled?
      @account_filters_enabled == true
    end

    def tenant_profile_filter?(profile_id, axis:)
      return false if profile_id.blank? || !account_filters_enabled?

      @selected_tenant.profiles.where(id: profile_id, axis: axis).exists?
    end

    def hierarchy_filter_ids
      user = @selected_tenant.admin_users.account_members.find_by(id: @hierarchy_user_id)
      return [] unless user

      [user.id] + user.descendant_ids
    end

    def hierarchy_users_payload(tenant)
      return [] unless tenant

      tenant.admin_users.account_members.includes(:profile).order(:name).map do |user|
        {
          id: user.id,
          name: user.name,
          profile_id: user.profile_id,
          profile_name: user.profile&.name,
          manager_id: user.manager_id
        }
      end
    end

    def start_system_impersonation!(user, return_to:, reason:)
      session[:impersonator_admin_user_id] = current_admin_user.id
      session[:impersonator_return_to] = return_to
      bypass_sign_in(user, scope: :admin_user)

      AccessAuditLog.log!(
        event_type: "impersonation_start",
        result: "allowed",
        request: request,
        admin_user: user,
        reason: reason,
        metadata: {
          tenant_id: user.tenant_id,
          impersonator_admin_user_id: session[:impersonator_admin_user_id],
          impersonated_admin_user_id: user.id,
          impersonated_system_admin: user.system_admin?
        }.compact
      )
    end

    def after_system_impersonation_path(user)
      user.system_admin? ? admin_system_path : admin_root_path
    end

    def system_impersonation_notice(user)
      tenant_label = user.system_admin? ? "Plataforma" : user.tenant&.name
      "Você está acessando #{tenant_label} como #{user.name}."
    end

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

    def tenant_owner_for(tenant)
      tenant.admin_users
        .account_members
        .active
        .joins(:profile)
        .where(profiles: { key: "tenant_owner", axis: Profile::AXES[:vertical] })
        .order(:name)
        .first
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

module Admin
  class AdminUsersController < BaseController
    before_action -> { check_permission!(:manage, :corretores) }
    before_action :set_admin_user, only: %i[show edit update destroy impersonate]
    before_action :require_admin!, only: %i[impersonate]

    def sync_from_vista
      status = Vista::SyncStatusService.new.snapshot
      if status[:status] == "processing"
        redirect_to admin_admin_users_path, alert: "Uma sincronização já está em andamento."
        return
      end

      Vista::ImportAgentsJob.perform_later
      redirect_to admin_admin_users_path,
                  notice: "Sincronização de corretores do Vista iniciada em background."
    end

    def vista_sync_status
      @status = Vista::SyncStatusService.new.snapshot
      render partial: "admin/admin_users/vista_sync_panel", locals: { status: @status }
    end

    def backfill_brokers
      status = Vista::SyncStatusService.new(namespace: "brokers_backfill").snapshot
      if status[:status] == "processing"
        redirect_to admin_admin_users_path, alert: "Backfill já está em andamento."
        return
      end

      Vista::BackfillBrokersJob.perform_later
      redirect_to admin_admin_users_path,
                  notice: "Backfill de corretores nos imóveis iniciado em background."
    end

    def backfill_brokers_status
      @status = Vista::SyncStatusService.new(namespace: "brokers_backfill").snapshot
      render partial: "admin/admin_users/backfill_brokers_panel", locals: { status: @status }
    end

    def index
      @admin_users = AdminUser.includes(:profile, :manager)

      if params[:query].present?
        q = "%#{params[:query]}%"
        @admin_users = @admin_users.where("name ILIKE ? OR email ILIKE ? OR vista_id ILIKE ? OR creci ILIKE ?", q, q, q, q)
      end

      if params[:profile_id].present?
        @admin_users = @admin_users.where(profile_id: params[:profile_id])
      end

      case params[:status]
      when "active"   then @admin_users = @admin_users.active
      when "inactive" then @admin_users = @admin_users.inactive
      end

      @admin_users = @admin_users.order(name: :asc).paginate(page: params[:page], per_page: 20)
    end

    def show
    end

    def new
      @admin_user = AdminUser.new
    end

    def edit
    end

    def create
      @admin_user = AdminUser.new(admin_user_params)
      if @admin_user.save
        redirect_to admin_admin_users_path, notice: 'Usuário criado com sucesso.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if params[:admin_user][:password].blank?
        params[:admin_user].delete(:password)
        params[:admin_user].delete(:password_confirmation)
      end

      if @admin_user.update(admin_user_params)
        redirect_to admin_admin_users_path, notice: 'Usuário atualizado com sucesso.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @admin_user.destroy
      redirect_to admin_admin_users_path, notice: 'Usuário excluído com sucesso.'
    end

    def impersonate
      if @admin_user == current_admin_user
        redirect_to admin_admin_users_path, alert: "Você já está logado como este usuário."
        return
      end

      session[:impersonator_admin_user_id] = current_admin_user.id
      session[:impersonator_return_to] = request.referer.presence || admin_admin_users_path
      bypass_sign_in(@admin_user, scope: :admin_user)

      AccessAuditLog.log!(
        event_type: "impersonation_start",
        result: "allowed",
        request: request,
        admin_user: @admin_user,
        reason: "Admin iniciou impersonação",
        metadata: {
          impersonator_admin_user_id: session[:impersonator_admin_user_id],
          impersonated_admin_user_id: @admin_user.id
        }
      )

      redirect_to admin_root_path, notice: "Você está acessando como #{@admin_user.name}."
    end

    private

    def set_admin_user
      @admin_user = AdminUser.find(params[:id])
    end

    def admin_user_params
      params.require(:admin_user).permit(:email, :password, :password_confirmation, :name, :role, :profile_id, :manager_id, :creci, :phone, :biography, :birth_date, :city, :avatar, :acting_type, :active, :display_on_site, :field_agent_enabled, :default_store_id, :require_ip_allowlist, :require_trusted_device)
    end
  end
end

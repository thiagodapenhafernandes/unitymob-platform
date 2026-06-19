module Admin
  class AdminUsersController < BaseController
    before_action -> { check_permission!(:manage, :corretores) }
    before_action :set_admin_user, only: %i[show edit update destroy impersonate]
    before_action :require_admin!, only: %i[impersonate move_hierarchy]

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
      @admin_users = AdminUser.account_members.includes(:profile, :manager).with_attached_avatar

      if params[:query].present?
        q = "%#{params[:query]}%"
        @admin_users = @admin_users.where("name ILIKE ? OR email ILIKE ? OR vista_id ILIKE ? OR creci ILIKE ?", q, q, q, q)
      end

      if params[:profile_id].present?
        @admin_users = @admin_users.where(profile_id: params[:profile_id])
      end

      if params[:acting_type].present? && AdminUser.acting_types.key?(params[:acting_type])
        @admin_users = @admin_users.where(acting_type: params[:acting_type])
      end

      if params[:manager_id].present?
        manager = AdminUser.find_by(id: params[:manager_id])
        @admin_users = @admin_users.where(id: manager ? manager.descendant_ids : [])
      end

      case params[:status]
      when "active"   then @admin_users = @admin_users.active
      when "inactive" then @admin_users = @admin_users.inactive
      end

      stats_scope = @admin_users.except(:includes, :preload, :eager_load, :order, :limit, :offset)
      @total_admin_users = stats_scope.count
      @active_admin_users = stats_scope.active.count
      @inactive_admin_users = stats_scope.inactive.count
      @displayed_admin_users = stats_scope.displayed_on_site.count
      @available_profiles = Profile.order(:name)
      @manager_options = AdminUser.account_members
        .where(id: AdminUser.where.not(manager_id: nil).select(:manager_id))
        .order(:name)
      @vista_sync_status = Vista::SyncStatusService.new.snapshot
      @brokers_backfill_status = Vista::SyncStatusService.new(namespace: "brokers_backfill").snapshot

      @admin_users = @admin_users.order(name: :asc).paginate(page: params[:page], per_page: 20)
      @selected_admin_user = @admin_users.first
      @habitations_count_by_admin_user = Habitation
        .where(admin_user_id: @admin_users.map(&:id))
        .group(:admin_user_id)
        .count
    end

    # Árvore de hierarquia (gestor -> subordinados), montada em memória para evitar N+1.
    # Perfis "Administrativo" não fazem parte do organograma e são omitidos; subordinados
    # que ficarem sem gestor presente sobem para a raiz (ninguém some além deles).
    def hierarchy
      @all_users = AdminUser.account_members.includes(:profile).with_attached_avatar
        .order(Arel.sql("hierarchy_position ASC NULLS LAST, name ASC")).to_a
        .reject { |u| u.profile&.administrativo? }
      @can_reorganize = current_admin_user.admin?
      present_ids = @all_users.map(&:id).to_set
      @children_by_manager = @all_users.group_by { |u| present_ids.include?(u.manager_id) ? u.manager_id : nil }
      @roots = @children_by_manager[nil] || []

      @descendant_count = {}
      count_desc = lambda do |uid|
        kids = @children_by_manager[uid] || []
        total = kids.sum { |kid| 1 + count_desc.call(kid.id) }
        @descendant_count[uid] = total
        total
      end
      @roots.each { |root| count_desc.call(root.id) }

      @habitations_count_by_admin_user = Habitation
        .where(admin_user_id: @all_users.map(&:id))
        .group(:admin_user_id)
        .count
      @habitations_count_by_admin_user.default = 0

      @total_users = @all_users.size
      @active_users = @all_users.count(&:active)
      @manager_count = @children_by_manager.keys.compact.size
    end

    # Persiste um arraste na árvore: re-parent (manager_id) + ordem dos irmãos.
    # Apenas admins (before_action :require_admin!). Bloqueia ciclos.
    def move_hierarchy
      user = AdminUser.find(params[:id])
      new_manager_id = params[:manager_id].presence
      new_manager = new_manager_id ? AdminUser.find(new_manager_id) : nil

      if new_manager && (new_manager.id == user.id || user.descendant_ids.include?(new_manager.id))
        return render json: { ok: false, error: "Movimento inválido: criaria um ciclo na hierarquia." }, status: :unprocessable_entity
      end

      sibling_ids = Array(params[:sibling_ids]).map(&:to_i)

      ActiveRecord::Base.transaction do
        user.update!(manager_id: new_manager&.id)
        sibling_ids.each_with_index do |sid, idx|
          AdminUser.where(id: sid).update_all(hierarchy_position: idx)
        end
      end

      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { ok: false, error: "Usuário não encontrado." }, status: :not_found
    rescue => e
      render json: { ok: false, error: e.message }, status: :unprocessable_entity
    end

    def show
      @subordinates = @admin_user.subordinates.includes(:profile).order(:name)
      @habitations_count = Habitation.where(admin_user_id: @admin_user.id).count
      @total_descendants = @admin_user.total_descendants_count
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
      if @admin_user == current_admin_user
        redirect_to admin_admin_users_path, alert: "Você não pode excluir o próprio usuário."
        return
      end

      target = AdminUser.find_by(id: params[:reassign_to_id]) || current_admin_user
      if target.nil? || target.id == @admin_user.id
        redirect_to admin_admin_users_path, alert: "Escolha outro usuário para herdar os dados do excluído."
        return
      end

      AdminUsers::HardDeleter.call(user: @admin_user, target: target)
      redirect_to admin_admin_users_path,
                  notice: "Usuário excluído. Carteira (leads, imóveis, tarefas...) reatribuída para #{target.name}."
    rescue AdminUsers::HardDeleter::Error, ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      redirect_to admin_admin_users_path, alert: "Não foi possível excluir o usuário: #{e.message}"
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
      permitted = [:email, :password, :password_confirmation, :name, :role, :profile_id, :manager_id, :creci, :phone, :biography, :birth_date, :city, :avatar, :acting_type, :active, :display_on_site, :field_agent_enabled, :default_store_id, :require_ip_allowlist, :require_trusted_device]
      # Conceder/revogar "Admin do Sistema" só pode ser feito por um Admin do Sistema.
      permitted << :super_admin if current_admin_user&.system_admin?
      params.require(:admin_user).permit(*permitted)
    end
  end
end

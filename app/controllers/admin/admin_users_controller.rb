module Admin
  class AdminUsersController < BaseController
    before_action -> { check_permission!(:manage, :corretores) }
    before_action :set_admin_user, only: %i[show edit update destroy]
    before_action :authorize_admin_user_management!, only: %i[show edit update destroy]
    before_action :authorize_hierarchy_management!, only: %i[new create move_hierarchy]
    before_action :load_access_options, only: %i[new edit create update]

    def sync_from_vista
      if current_tenant.blank?
        redirect_to admin_admin_users_path, alert: "Selecione uma conta para sincronizar corretores do Vista."
        return
      end

      status = Vista::SyncStatusService.new.snapshot
      if status[:status] == "processing"
        redirect_to admin_admin_users_path, alert: "Uma sincronização já está em andamento."
        return
      end

      Vista::ImportAgentsJob.perform_later(tenant_id: current_tenant.id)
      redirect_to admin_admin_users_path,
                  notice: "Sincronização de corretores do Vista iniciada em background."
    end

    def vista_sync_status
      @status = Vista::SyncStatusService.new.snapshot
      render partial: "admin/admin_users/vista_sync_panel", locals: { status: @status }
    end

    def backfill_brokers
      if current_tenant.blank?
        redirect_to admin_admin_users_path, alert: "Selecione uma conta para executar o backfill de corretores."
        return
      end

      status = Vista::SyncStatusService.new(namespace: "brokers_backfill").snapshot
      if status[:status] == "processing"
        redirect_to admin_admin_users_path, alert: "Backfill já está em andamento."
        return
      end

      Vista::BackfillBrokersJob.perform_later(tenant_id: current_tenant.id)
      redirect_to admin_admin_users_path,
                  notice: "Backfill de corretores nos imóveis iniciado em background."
    end

    def backfill_brokers_status
      @status = Vista::SyncStatusService.new(namespace: "brokers_backfill").snapshot
      render partial: "admin/admin_users/backfill_brokers_panel", locals: { status: @status }
    end

    def index
      @admin_users = manageable_admin_users_scope.includes(:profile, :horizontal_profile, :manager, :rentals_manager).with_attached_avatar

      if params[:query].present?
        q = "%#{params[:query]}%"
        @admin_users = @admin_users.where("name ILIKE ? OR email ILIKE ? OR vista_id ILIKE ? OR creci ILIKE ?", q, q, q, q)
      end

      if params[:profile_id].present?
        selected_profile = current_tenant.profiles.find_by(id: params[:profile_id])
        @admin_users = @admin_users.matching_access_profile(selected_profile) if selected_profile
      end

      if params[:acting_type].present? && AdminUser.acting_types.key?(params[:acting_type])
        @admin_users = @admin_users.where(acting_type: params[:acting_type])
      end

      if params[:manager_id].present?
        manager = current_tenant.admin_users.find_by(id: params[:manager_id])
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
      @available_profiles = assignable_access_profiles
      manager_ids = current_tenant.admin_users.where.not(manager_id: nil).pluck(:manager_id)
      if AdminUser.column_names.include?("rentals_manager_id")
        manager_ids += current_tenant.admin_users.where.not(rentals_manager_id: nil).pluck(:rentals_manager_id)
      end
      @manager_options = current_tenant.admin_users.account_members.where(id: manager_ids.compact.uniq).order(:name)
      @manager_options = @manager_options.where(id: visible_admin_user_ids) unless visible_admin_user_ids.nil?
      @vista_sync_status = Vista::SyncStatusService.new.snapshot
      @brokers_backfill_status = Vista::SyncStatusService.new(namespace: "brokers_backfill").snapshot

      @admin_users = @admin_users.order(name: :asc).paginate(page: params[:page], per_page: 20)
      @selected_admin_user = @admin_users.first
      @habitations_count_by_admin_user = current_tenant.habitations
        .where(admin_user_id: @admin_users.map(&:id))
        .group(:admin_user_id)
        .count
    end

    # Árvore de hierarquia (gestor -> subordinados), montada em memória para evitar N+1.
    # Admins do Sistema ficam fora da conta; todos os perfis verticais do Tenant entram
    # no organograma, inclusive perfis customizados entre Tenant Owner e Agent.
    def hierarchy
      # Hierarquia mostra APENAS usuários ativos (inativo já está fora da
      # operação); left_joins mantém os sem perfil vertical visíveis, marcados
      # como fora da hierarquia/distribuição.
      @all_users = manageable_admin_users_scope.where(active: true)
        .includes(:profile, :horizontal_profile).with_attached_avatar
        .left_joins(:profile)
        .where("profiles.axis = :vertical OR admin_users.profile_id IS NULL", vertical: Profile::AXES[:vertical])
        .order(Arel.sql("admin_users.hierarchy_position ASC NULLS LAST, admin_users.name ASC")).to_a

      # Regra dinâmica da distribuição: existindo perfil vertical acima do
      # perfil do usuário (além do dono), o vínculo com gestor é obrigatório.
      vertical_positions = current_tenant.profiles.vertical.where.not(key: "tenant_owner")
                                         .where.not(position: nil).order(:position).pluck(:position)
      @min_gestor_position = vertical_positions.first
      @can_reorganize = tenant_owner? || current_admin_user.can?(:manage, :corretores)

      # Funções operacionais (perfil horizontal) não são nós de gestão: viram
      # chips no nó do gestor (se tiverem um) ou no bloco "Equipe interna".
      @internal_users, @all_users = @all_users.partition { |u| u.horizontal_profile_id.present? }

      present_ids = @all_users.map(&:id).to_set
      @internal_by_manager = @internal_users.select { |u| u.manager_id.present? && present_ids.include?(u.manager_id) }
                                            .group_by(&:manager_id)
      @internal_unanchored = @internal_users - @internal_by_manager.values.flatten
      rentals_ready = AdminUser.column_names.include?("rentals_manager_id")

      # Vínculos POR ÁREA: quem atua em Ambos aparece nas duas equipes
      # (venda sob manager_id, locação sob rentals_manager_id).
      @children_by_manager = Hash.new { |h, k| h[k] = [] }
      @all_users.each do |u|
        links = []
        links << [u.manager_id, :venda] if u.manager_id.present? && present_ids.include?(u.manager_id)
        if rentals_ready && u.rentals_manager_id.present? && present_ids.include?(u.rentals_manager_id) && u.rentals_manager_id != u.manager_id
          links << [u.rentals_manager_id, :locacao]
        end
        links = [[nil, nil]] if links.empty?
        links.each { |manager_id, area| @children_by_manager[manager_id] << { user: u, area: area } }
      end
      @roots = (@children_by_manager[nil] || []).map { |entry| entry[:user] }

      @descendant_count = {}
      count_desc = lambda do |uid|
        return @descendant_count[uid] if @descendant_count.key?(uid)

        @descendant_count[uid] = 0 # guarda anti-reentrância
        kids = @children_by_manager[uid] || []
        total = kids.sum { |entry| 1 + count_desc.call(entry[:user].id) }
        @descendant_count[uid] = total
        total
      end
      @roots.each { |root| count_desc.call(root.id) }

      @habitations_count_by_admin_user = current_tenant.habitations
        .where(admin_user_id: @all_users.map(&:id))
        .group(:admin_user_id)
        .count
      @habitations_count_by_admin_user.default = 0

      @total_users = @all_users.size + @internal_users.size
      @active_users = @all_users.count(&:active) + @internal_users.count(&:active)
      @manager_count = @children_by_manager.keys.compact.size
    end

    # Persiste um arraste na árvore: re-parent (manager_id) + ordem dos irmãos.
    # Tenant Owner e gestores autorizados podem reorganizar apenas dentro do próprio escopo.
    def move_hierarchy
      user = manageable_admin_users_scope.find(params[:id])
      new_manager_id = params[:manager_id].presence
      new_manager = new_manager_id ? current_tenant.admin_users.find(new_manager_id) : nil

      if new_manager && (new_manager.id == user.id || user.descendant_ids.include?(new_manager.id))
        return render json: { ok: false, error: "Movimento inválido: criaria um ciclo na hierarquia." }, status: :unprocessable_entity
      end

      if new_manager && !new_manager.manager_candidate_for?(user)
        return render json: { ok: false, error: "Gestor precisa estar acima do usuário na hierarquia vertical." }, status: :unprocessable_entity
      end

      unless new_manager.nil? || current_admin_user.can_manage_user?(new_manager) || new_manager == current_admin_user
        return render json: { ok: false, error: "Gestor fora do seu escopo hierárquico." }, status: :unprocessable_entity
      end

      sibling_ids = Array(params[:sibling_ids]).map(&:to_i)

      # Área decide o vínculo gravado: quem atua só em Locação é ancorado via
      # rentals_manager_id (o alinhamento gestor×área zeraria manager_id).
      manager_field =
        if user.acting_type.to_s == "rentals" && user.has_attribute?(:rentals_manager_id)
          :rentals_manager_id
        else
          :manager_id
        end

      ActiveRecord::Base.transaction do
        user.update!(manager_field => new_manager&.id)
        sibling_ids.each_with_index do |sid, idx|
          current_tenant.admin_users.where(id: sid).update_all(hierarchy_position: idx)
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
      @habitations_count = current_tenant.habitations.where(admin_user_id: @admin_user.id).count
      @total_descendants = @admin_user.total_descendants_count
    end

    def new
      @admin_user = current_tenant.admin_users.new
      @admin_user.manager = current_admin_user unless tenant_owner?
    end

    def edit
    end

    def create
      @admin_user = current_tenant.admin_users.new(admin_user_params)
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

      reassign_scope = current_tenant.admin_users.account_members
      reassign_scope = reassign_scope.where(id: [current_admin_user.id] + current_admin_user.descendant_ids) unless tenant_owner?
      target = reassign_scope.find_by(id: params[:reassign_to_id]) || current_admin_user
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

    private

    def set_admin_user
      @admin_user = current_tenant.admin_users.find(params[:id])
    end

    def authorize_admin_user_management!
      return if current_admin_user&.can_manage_user?(@admin_user)

      redirect_to admin_admin_users_path, alert: "Você não tem permissão para gerenciar este usuário."
    end

    def authorize_hierarchy_management!
      return if tenant_owner?
      return if current_admin_user&.can?(:manage, :corretores) && current_admin_user.vertical_profile.present?

      redirect_to admin_admin_users_path, alert: "Você não tem permissão para gerenciar hierarquia."
    end

    def manageable_admin_users_scope
      ids = visible_admin_user_ids
      scope = current_tenant.admin_users.account_members
      ids.nil? ? scope : scope.where(id: ids)
    end

    def visible_admin_user_ids
      return nil if tenant_owner?

      current_admin_user&.descendant_ids || []
    end

    def assignable_vertical_profiles
      scope = current_tenant.profiles.vertical.where(active: true).order(Arel.sql("position ASC NULLS LAST, name ASC"))
      return scope if tenant_owner?

      current_position = current_admin_user&.vertical_profile&.position.to_i
      scope.where("position > ?", current_position)
    end

    def assignable_horizontal_profiles
      scope = current_tenant.profiles.horizontal.where(active: true).includes(:vertical_profile).order(:name)
      return scope if tenant_owner?

      # âncoras podem ser encadeadas: o que vale é a RAIZ vertical da função
      allowed_vertical_ids = assignable_vertical_profiles.pluck(:id).to_set
      scope.select { |profile| allowed_vertical_ids.include?(profile.root_vertical_profile&.id) }
    end

    def assignable_access_profiles
      profiles = assignable_vertical_profiles.to_a + Array(assignable_horizontal_profiles)
      profiles.sort_by { |profile| [profile.vertical? ? 0 : 1, profile.vertical? ? profile.position.to_i : profile.root_vertical_profile&.position.to_i || 10_000, profile.name.to_s.downcase] }
    end

    def load_access_options
      @assignable_vertical_profiles = assignable_vertical_profiles
      @assignable_horizontal_profiles = assignable_horizontal_profiles
      @assignable_manager_options = current_tenant.admin_users.account_members.includes(:profile).order(:name).select do |candidate|
        next true if @admin_user.blank? || @admin_user.new_record? && candidate == current_admin_user

        candidate.manager_candidate_for?(@admin_user) &&
          (tenant_owner? || candidate == current_admin_user || current_admin_user.can_manage_user?(candidate))
      end
    end

    public

    # Dono da conta pode RESETAR o 2FA de um usuário que perdeu o aparelho e os
    # backup codes (antes: só via console). O usuário volta a logar só com senha
    # e reativa o 2FA no perfil (ou é forçado, se a conta exigir).
    def reset_two_factor
      unless tenant_owner?
        redirect_to admin_admin_users_path, alert: "Apenas o Dono da conta pode resetar a verificação em duas etapas."
        return
      end

      user = current_tenant.admin_users.find(params[:id])
      user.update!(otp_secret: nil, otp_enabled_at: nil, otp_backup_codes: [], otp_consumed_timestep: nil)
      AccessAuditLog.log!(event_type: "two_factor_disabled", result: "allowed", request: request,
                          admin_user: user, reason: "2FA resetado pelo Dono da conta",
                          metadata: { reset_by: current_admin_user.id }) rescue nil
      redirect_to edit_admin_admin_user_path(user), notice: "Verificação em duas etapas resetada — #{user.name} volta a entrar só com a senha."
    end

    private

    def admin_user_params
      permitted = [:email, :password, :password_confirmation, :name, :creci, :phone, :biography, :birth_date, :city, :avatar, :acting_type, :active, :display_on_site, :field_agent_enabled, :default_store_id]
      permitted.concat([:profile_id, :horizontal_profile_id, :access_profile_id, :manager_id, :rentals_manager_id]) if current_admin_user&.can?(:manage, :corretores)
      permitted.concat([:require_ip_allowlist, :require_trusted_device]) if tenant_owner?
      attrs = params.require(:admin_user).permit(*permitted)
      # Usuário espelho (multi-conta): e-mail sintético e senha pertencem ao
      # primário — nunca editáveis por esta conta (UI esconde; aqui é a trava real).
      if @admin_user&.respond_to?(:mirror?) && @admin_user&.mirror?
        attrs.delete(:email)
        attrs.delete(:password)
        attrs.delete(:password_confirmation)
      end
      restrict_profile_params_to_current_tenant(attrs)
    end

    # Select único "Perfil de acesso": o EIXO é decidido aqui. Perfil vertical
    # define a hierarquia (e limpa a função); perfil horizontal carrega junto o
    # vertical-pai a que pertence — o usuário nunca escolhe os dois.
    def resolve_access_profile!(attrs)
      raw_id = attrs.delete(:access_profile_id)
      return if raw_id.blank?

      profile = current_tenant.profiles.find_by(id: raw_id)
      return if profile.nil?

      if profile.vertical?
        attrs[:profile_id] = profile.id
        attrs[:horizontal_profile_id] = nil
      else
        attrs[:profile_id] = profile.root_vertical_profile&.id
        attrs[:horizontal_profile_id] = profile.id
        attrs[:manager_id] = nil # função operacional fica fora da árvore de gestão
        attrs[:rentals_manager_id] = nil
      end
    end

    def restrict_profile_params_to_current_tenant(attrs)
      resolve_access_profile!(attrs)

      selected_profile = attrs[:profile_id].present? ? assignable_vertical_profiles.find_by(id: attrs[:profile_id]) : nil

      if attrs[:profile_id].present? && selected_profile.blank?
        attrs.delete(:profile_id)
        selected_profile = nil
      end

      if attrs[:horizontal_profile_id].present? && assignable_horizontal_profiles.none? { |p| p.id == attrs[:horizontal_profile_id].to_i }
        attrs.delete(:horizontal_profile_id)
      end

      if attrs[:horizontal_profile_id].present? && selected_profile
        horizontal = assignable_horizontal_profiles.find { |p| p.id == attrs[:horizontal_profile_id].to_i }
        attrs.delete(:horizontal_profile_id) if horizontal&.root_vertical_profile&.id != selected_profile.id
      end

      manager_scope = current_tenant.admin_users.account_members
      manager_scope = manager_scope.where(id: [current_admin_user.id] + current_admin_user.descendant_ids) unless tenant_owner?

      if attrs[:manager_id].present? && !manager_scope.exists?(id: attrs[:manager_id])
        attrs.delete(:manager_id)
      end

      if attrs[:rentals_manager_id].present? && !manager_scope.exists?(id: attrs[:rentals_manager_id])
        attrs.delete(:rentals_manager_id)
      end

      if attrs[:manager_id].present? && selected_profile
        manager = current_tenant.admin_users.find_by(id: attrs[:manager_id])
        attrs.delete(:manager_id) if manager&.profile&.position.to_i >= selected_profile.position.to_i
      end

      attrs
    end

  end
end

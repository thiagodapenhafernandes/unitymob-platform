module Admin
  class ProfilesController < BaseController
    before_action :require_profile_governance_admin!
    before_action :set_profile, only: %i[show edit update destroy]

    def index
      @vertical_profiles = current_tenant.profiles.ordered_vertical.includes(:horizontal_profiles)
      @horizontal_profiles = current_tenant.profiles.ordered_horizontal.includes(:vertical_profile)
      @profiles = @vertical_profiles + @horizontal_profiles
      @users_count_by_profile_id = profile_user_counts

      # "Submetido a": vertical → vertical imediatamente acima na cadeia (menor
      # position acima); horizontal → o vertical em que está ancorado.
      ordered = @vertical_profiles.to_a
      @superior_profile = {}
      ordered.each_with_index do |profile, index|
        @superior_profile[profile.id] = index.positive? ? ordered[index - 1] : nil
      end
      @horizontal_profiles.each { |profile| @superior_profile[profile.id] = profile.vertical_profile }

      # Ordem final: TODOS os verticais primeiro (por posição, topo→base) e os
      # horizontais por último. Entre horizontais, âncora antes de quem depende
      # dela (Gestão Interna antes de Administrativo).
      horizontals = @horizontal_profiles.sort_by { |p| p.name.to_s.downcase }
      ordered_horizontals = []
      placed = {}
      remaining = horizontals.dup
      until remaining.empty?
        batch = remaining.select do |profile|
          superior = @superior_profile[profile.id]
          superior.nil? || superior.vertical? || placed[superior.id]
        end
        batch = remaining.first(1) if batch.empty? # anti-loop defensivo
        batch.each { |profile| ordered_horizontals << profile; placed[profile.id] = true }
        remaining -= batch
      end
      @ordered_profiles = ordered + ordered_horizontals
    end

    def show
    end

    def new
      @profile = current_tenant.profiles.new(active: true, axis: params[:axis].presence_in(Profile::AXES.values) || Profile::AXES[:vertical], permissions: default_permissions)
      @profile.vertical_profile_id = params[:vertical_profile_id] if @profile.horizontal?
    end

    def edit
    end

    def create
      attrs = profile_params_with_permissions
      @profile = current_tenant.profiles.new(attrs)
      if profile_position_error?
        render_profile_position_error(:new)
      elsif @profile.save
        redirect_to edit_admin_profile_path(@profile), notice: "Perfil criado. Configure as permissões."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      attrs = profile_params_with_permissions
      if profile_position_error?
        @profile.assign_attributes(attrs)
        render_profile_position_error(:edit)
      elsif update_profile_with_structural_reconciliation(attrs)
        redirect_to admin_profiles_path, notice: "Perfil e permissões atualizados."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @profile.locked?
        redirect_to admin_profiles_path, alert: "Perfis fixos da hierarquia não podem ser excluídos."
        return
      end

      blocking_message = profile_destroy_blocking_message
      if blocking_message.present?
        redirect_to admin_profiles_path, alert: blocking_message
      elsif @profile.destroy
        redirect_to admin_profiles_path, notice: "Perfil excluído."
      else
        redirect_to admin_profiles_path, alert: @profile.errors.full_messages.to_sentence.presence || "Não foi possível excluir o perfil."
      end
    end

    private

    def profile_user_counts
      vertical_counts = current_tenant.admin_users
        .where(profile_id: @vertical_profiles.map(&:id))
        .group(:profile_id)
        .count
      horizontal_counts = current_tenant.admin_users
        .where(horizontal_profile_id: @horizontal_profiles.map(&:id))
        .group(:horizontal_profile_id)
        .count

      vertical_counts.merge(horizontal_counts)
    end

    def set_profile
      @profile = current_tenant.profiles.find(params[:id])
    end

    def profile_params
      permitted = params.require(:profile).permit(:name, :active, :axis, :vertical_profile_id, :position, :insert_after_profile_id)
      insert_after_profile_id = permitted.delete(:insert_after_profile_id)
      permitted[:axis] = permitted[:axis].presence_in(Profile::AXES.values) || Profile::AXES[:vertical]
      permitted[:vertical_profile_id] = nil if permitted[:axis] == Profile::AXES[:vertical]
      if permitted[:axis] == Profile::AXES[:vertical] && insert_after_profile_id.present?
        permitted[:position] = vertical_position_after(insert_after_profile_id)
      end
      permitted
    end

    # Normaliza a entrada da matriz de checkboxes no permissions JSONB.
    # Estrutura esperada:
    #   params[:profile][:permissions][:admin] = "1" | "0"
    #   params[:profile][:permissions][:imoveis][:view] = "1"
    #   params[:profile][:permissions][:imoveis][:scope] = "own" | "team" | "all"
    def profile_params_with_permissions
      base = profile_params

      raw = params.dig(:profile, :permissions) || {}
      perms = {}

      perms["admin"] = truthy?(raw[:admin])

      Profile::RESOURCES.each do |res|
        key = res[:key]
        entry = raw[key] || {}
        res_perms = {}
        res[:actions].each do |action|
          res_perms[action] = truthy?(entry[action])
        end
        if res[:scopeable]
          scope = entry[:scope].presence_in(%w[own team all]) || "own"
          # Somente o eixo vertical carrega hierarquia. Em perfis horizontais,
          # "all" é neutro e "own" pode apenas restringir o nível vertical.
          scope = "all" if base[:axis] == Profile::AXES[:horizontal] && scope == "team"
          res_perms["scope"] = scope
        end
        perms[key] = res_perms
      end

      base.merge(permissions: perms)
    end

    def truthy?(value)
      value.to_s.in?(%w[1 true on yes])
    end

    def default_permissions
      params[:axis] == Profile::AXES[:horizontal] ? {} : Profile.default_permissions_for("Corretor")
    end

    def vertical_position_after(profile_id)
      @profile_position_error = nil
      previous_profile = current_tenant.profiles.vertical.find_by(id: profile_id)
      if previous_profile.blank? || previous_profile.agent? || previous_profile.id == @profile&.id
        @profile_position_error = "Selecione um perfil vertical acima do Agent."
        return nil
      end
      return @profile.position if profile_already_positioned_after?(previous_profile)

      next_profile = current_tenant.profiles.vertical
        .where.not(id: @profile&.id)
        .where("position > ?", previous_profile.position)
        .order(:position)
        .first
      next_position = next_profile&.position || 10_000
      if next_position - previous_profile.position <= 1
        return rebalance_vertical_positions_after(previous_profile)
      end

      previous_profile.position + ((next_position - previous_profile.position) / 2)
    end

    def rebalance_vertical_positions_after(previous_profile)
      ordered_profiles = current_tenant.profiles.vertical
        .where.not(id: @profile&.id)
        .order(Arel.sql("position ASC NULLS LAST, id ASC"))
        .to_a

      insert_index = ordered_profiles.index { |profile| profile.id == previous_profile.id }
      if insert_index.nil? || previous_profile.agent?
        @profile_position_error = "Selecione um perfil vertical acima do Agent."
        return nil
      end

      ordered_with_placeholder = ordered_profiles.dup
      ordered_with_placeholder.insert(insert_index + 1, :target_profile)
      custom_slots = ordered_with_placeholder.reject do |entry|
        entry.respond_to?(:tenant_owner?) && entry.tenant_owner? ||
          entry.respond_to?(:agent?) && entry.agent?
      end

      if custom_slots.size >= 10_000
        @profile_position_error = "A hierarquia atingiu o limite de perfis verticais customizados."
        return nil
      end

      step = 10_000 / (custom_slots.size + 1)
      target_position = nil

      current_tenant.profiles.transaction do
        custom_slots.each_with_index do |entry, index|
          position = (index + 1) * step
          if entry == :target_profile
            target_position = position
          else
            entry.update_columns(position: position, updated_at: Time.current)
          end
        end
      end

      target_position
    end

    def profile_already_positioned_after?(previous_profile)
      return false unless @profile&.persisted? && @profile.vertical? && @profile.position.present?
      return false unless previous_profile.position.to_i < @profile.position.to_i

      current_tenant.profiles.vertical
        .where.not(id: @profile.id)
        .where("position > ? AND position < ?", previous_profile.position, @profile.position)
        .none?
    end

    def profile_position_error?
      @profile_position_error.present?
    end

    def render_profile_position_error(template)
      @profile.errors.add(:position, @profile_position_error)
      render template, status: :unprocessable_entity
    end

    def profile_destroy_blocking_message
      if @profile.admin_users.exists? || @profile.horizontal_admin_users.exists?
        return "Não é possível excluir: há usuários vinculados a este perfil."
      end

      linked_horizontal_profiles = @profile.horizontal_profiles.order(:name)
      return unless linked_horizontal_profiles.exists?

      names = linked_horizontal_profiles.limit(4).pluck(:name)
      remaining = linked_horizontal_profiles.count - names.size
      listed_names = names.to_sentence
      listed_names = "#{listed_names} e mais #{remaining}" if remaining.positive?
      "Não é possível excluir: este perfil é base das funções horizontais #{listed_names}. Edite essas funções e altere o campo “Vinculado a” para outro perfil, ou exclua essas funções primeiro."
    end

    def update_profile_with_structural_reconciliation(attrs)
      previous_axis = @profile.axis
      previous_vertical_profile_id = @profile.vertical_profile_id

      current_tenant.profiles.transaction do
        return false unless @profile.update(attrs)

        reconcile_profile_users_after_structure_change!(
          previous_axis: previous_axis,
          previous_vertical_profile_id: previous_vertical_profile_id
        )
      end

      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
      @profile.errors.add(:base, "Não foi possível atualizar a estrutura do perfil: #{e.message}")
      false
    end

    def reconcile_profile_users_after_structure_change!(previous_axis:, previous_vertical_profile_id:)
      return unless profile_structure_changed?(previous_axis: previous_axis, previous_vertical_profile_id: previous_vertical_profile_id)

      if @profile.horizontal?
        reconcile_users_for_horizontal_profile!
      else
        reconcile_users_for_vertical_profile!
      end
    end

    def profile_structure_changed?(previous_axis:, previous_vertical_profile_id:)
      previous_axis != @profile.axis || previous_vertical_profile_id != @profile.vertical_profile_id
    end

    def reconcile_users_for_horizontal_profile!
      target_vertical_profile_id = @profile.vertical_profile_id
      return if target_vertical_profile_id.blank?

      current_tenant.admin_users.where(profile_id: @profile.id).find_each do |user|
        user.update!(profile_id: target_vertical_profile_id, horizontal_profile_id: @profile.id, manager_id: nil)
      end

      current_tenant.admin_users.where(horizontal_profile_id: @profile.id).where.not(profile_id: target_vertical_profile_id).find_each do |user|
        user.update!(profile_id: target_vertical_profile_id, manager_id: nil)
      end
    end

    def reconcile_users_for_vertical_profile!
      current_tenant.admin_users.where(horizontal_profile_id: @profile.id).find_each do |user|
        user.update!(profile_id: @profile.id, horizontal_profile_id: nil, manager_id: nil)
      end
    end

    def require_profile_governance_admin!
      return if current_admin_user&.can_manage_profiles?

      redirect_to admin_root_path, alert: "Acesso negado. Apenas o Tenant Owner pode gerenciar perfis."
    end
  end
end

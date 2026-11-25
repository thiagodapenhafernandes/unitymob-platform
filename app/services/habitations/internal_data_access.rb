module Habitations
  # Escopo de consulta separado das permissões de alteração e das comissões.
  class InternalDataAccess
    def initialize(admin_user)
      @admin_user = admin_user
    end

    def configured?
      scope.present?
    end

    def allowed?(habitation)
      return false unless @admin_user && habitation && habitation.tenant_id == @admin_user.tenant_id
      return true if @admin_user.tenant_owner?
      return false unless @admin_user.can?(:view, :imoveis)
      return true if scope == "all"
      return false unless scope.in?(%w[own team])

      ids = scope == "team" ? @admin_user.team_scope_ids : [@admin_user.id]
      return true if habitation.admin_user_id.in?(ids)

      assignments = habitation.broker_assignments
      assignments.loaded? ? assignments.any? { |assignment| assignment.admin_user_id.in?(ids) } : assignments.exists?(admin_user_id: ids)
    end

    private

    def scope
      return @scope if defined?(@scope)

      vertical = @admin_user&.vertical_profile&.habitation_internal_data_scope
      horizontal = @admin_user&.horizontal_profile&.habitation_internal_data_scope
      @scope = if vertical && horizontal
        Profile.restricted_scope(vertical, horizontal)
      else
        horizontal || vertical
      end
    end
  end
end

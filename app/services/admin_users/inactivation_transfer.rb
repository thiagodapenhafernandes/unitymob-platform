module AdminUsers
  class InactivationTransfer
    Error = Class.new(StandardError)
    Result = Struct.new(:leads_count, :habitations_count, :broker_assignments_count, keyword_init: true)

    MODES = %w[reassign detach].freeze

    def self.call(user:, target: nil, mode: "reassign")
      new(user:, target:, mode:).call
    end

    def initialize(user:, target: nil, mode: "reassign")
      @user = user
      @target = target
      @mode = mode.to_s.presence || "reassign"
    end

    def call
      validate!

      result = Result.new(leads_count: 0, habitations_count: 0, broker_assignments_count: 0)
      now = Time.current

      ActiveRecord::Base.transaction do
        target_id = reassign? ? @target.id : nil

        result.leads_count = @user.tenant.leads
          .where(admin_user_id: @user.id)
          .update_all(admin_user_id: target_id, updated_at: now)

        result.habitations_count = @user.tenant.habitations
          .where(admin_user_id: @user.id)
          .update_all(admin_user_id: target_id, updated_at: now)

        result.broker_assignments_count = transfer_broker_assignments!(target_id:, now:)

        @user.update!(active: false, display_on_site: false)
      end

      result
    end

    private

    def validate!
      raise Error, "Usuário é obrigatório." if @user.blank?
      raise Error, "Ação de carteira inválida." unless MODES.include?(@mode)

      if reassign?
        raise Error, "Escolha um usuário ativo para receber a carteira." if @target.blank?
        raise Error, "Escolha um usuário diferente do inativado." if @target.id == @user.id
        raise Error, "Usuário destino precisa pertencer à mesma conta." if @target.tenant_id != @user.tenant_id
        raise Error, "Usuário destino precisa estar ativo." unless @target.active?
      end
    end

    def reassign?
      @mode == "reassign"
    end

    def transfer_broker_assignments!(target_id:, now:)
      scope = HabitationBrokerAssignment
        .joins(:habitation)
        .where(admin_user_id: @user.id, habitations: { tenant_id: @user.tenant_id })

      count = scope.count
      if reassign?
        scope.find_each do |assignment|
          duplicate = HabitationBrokerAssignment
            .where(habitation_id: assignment.habitation_id, admin_user_id: target_id, role: assignment.role)
            .where.not(id: assignment.id)
            .exists?

          if duplicate
            assignment.destroy!
          else
            assignment.update!(admin_user_id: target_id, updated_at: now)
          end
        end
      else
        scope.find_each(&:destroy!)
      end

      count
    end
  end
end

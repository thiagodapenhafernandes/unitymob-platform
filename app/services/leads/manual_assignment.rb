module Leads
  class ManualAssignment
    attr_reader :owner_changed, :notify_whatsapp

    def initialize(lead, actor:, attributes:, options: {})
      @lead, @actor, @attributes = lead, actor, attributes
      @invalid_options = options.values.any? { |value| ![nil, true, false, "0", "1", 0, 1].include?(value) }
      @notify_whatsapp = [true, "1", 1].include?(options[:notify_whatsapp])
      @rotate_queue = [true, "1", 1].include?(options[:rotate_queue])
    end

    def call
      invalid!("Opções de atribuição inválidas.") if @invalid_options
      unless @actor && (@actor.system_admin? || @actor.tenant_id == @lead.tenant_id)
        invalid!("Usuário sem permissão para atribuir leads desta conta.")
      end
      if actions_requested? && !(@actor&.admin? && @actor.tenant_id == @lead.tenant_id)
        invalid!("Somente o admin da conta pode notificar por WhatsApp ou girar a roleta na atribuição manual.")
      end

      @lead.with_lock do
        previous_owner_id = @lead.admin_user_id
        @lead.assign_attributes(@attributes)
        @owner_changed = @lead.will_save_change_to_admin_user_id?
        rule = assignment_rule! if @owner_changed && actions_requested?
        if @owner_changed && @rotate_queue
          rule.with_rotation_lock do
            @lead.save!
            rule.rotate_queue!(@lead.admin_user_id)
          end
        else
          @lead.save!
        end
        if @owner_changed && @lead.admin_user_id.present?
          @lead.activities.create!(kind: "assigned_directly", metadata: {
            reason: "manual_assignment", admin_user_id: @lead.admin_user_id,
            previous_admin_user_id: previous_owner_id, by_admin_user_id: @actor.id,
            rule_id: @lead.distribution_rule_id, notify_whatsapp_requested: @notify_whatsapp,
            queue_rotated: @rotate_queue
          })
        end
      end
      true
    rescue ActiveRecord::RecordInvalid => error
      @lead.errors.add(:base, "Não foi possível concluir a atribuição e atualizar a fila.") unless error.record == @lead
      false
    end

    private

    def actions_requested?
      @notify_whatsapp || @rotate_queue
    end

    def assignment_rule!
      invalid!("Selecione um corretor para a atribuição.") if @lead.admin_user_id.blank?
      invalid!("Não é possível notificar ou girar a roleta de um lead arquivado.") if @lead.archived_at.present?
      rule = if @lead.distribution_rule_id.present?
        @lead.tenant.distribution_rules.find_by(id: @lead.distribution_rule_id)
      else
        DistributorService.new(@lead).matching_entry_rule
      end
      invalid!("O lead precisa de uma fila ativa e compatível para notificar ou girar a roleta.") unless rule&.active?
      invalid!("A fila não recebe a modalidade deste lead.") unless rule.accepts_entry?(EntryClassification.new(@lead))
      candidates = rule.candidates_for(@lead, candidates: rule.candidates_filtered_by_checkin)
      unless candidates.exists?(admin_user_id: @lead.admin_user_id)
        invalid!("O corretor não está elegível nesta fila. Confira participantes, campanha e check-in.")
      end
      if rule.represamento_active? && rule.outside_represamento_hours?
        invalid!("A fila está fora do horário de atendimento.")
      end
      invalid!("Esta fila não usa roleta rotativa.") if @rotate_queue && !rule.rotary?
      invalid!("O WhatsApp está desativado nas notificações desta fila.") if @notify_whatsapp && !rule.notify_whatsapp?
      @lead.distribution_rule = rule
      rule
    end

    def invalid!(message)
      @lead.errors.add(:base, message)
      raise ActiveRecord::RecordInvalid, @lead
    end
  end
end

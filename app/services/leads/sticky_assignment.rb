module Leads
  # Fidelização (lead stickiness): se a pessoa do lead já foi atendida por um
  # corretor, devolve esse corretor para a distribuição, respeitando a config
  # da conta em LeadSetting (chave de match, dono anterior, fallback e janela).
  # Retorna nil quando desligado, sem match ou corretor inelegível.
  class StickyAssignment
    def self.corretor_for(lead, rule, candidates:)
      new(lead, rule, candidates).corretor
    end

    def initialize(lead, rule, candidates)
      @lead = lead
      @rule = rule
      @candidates = candidates
      @setting = LeadSetting.instance(tenant: lead.tenant)
    end

    # Quantos leads anteriores examinar na busca do dono elegível mais recente.
    MAX_PREVIOUS_LEADS = 25

    def corretor
      return nil unless @setting.stickiness_enabled?

      owner_id = previous_owner_id
      return nil if owner_id.blank?

      user = @lead.tenant.admin_users.find_by(id: owner_id)
      return nil unless eligible?(user)

      user
    end

    private

    # Dono elegível mais recente: recência pela criação (estável — um toque
    # incidental como sync externo, automação ou nota não rouba a fidelização)
    # e, se o dono mais recente for inelegível, tenta os anteriores em ordem
    # em vez de desistir direto para o rodízio.
    def previous_owner_id
      scope = base_scope
      return nil if scope.nil?

      owner_ids = scope.reorder(created_at: :desc, id: :desc)
                       .select(:admin_user_id, :lead_pipeline_stage_id)
                       .limit(MAX_PREVIOUS_LEADS)
                       .filter_map do |previous_lead|
                         next if @setting.non_fidelizing_stage_for_stickiness?(previous_lead.lead_pipeline_stage_id)

                         previous_lead.admin_user_id
                       end.uniq
      return nil if owner_ids.empty?

      users_by_id = @lead.tenant.admin_users.where(id: owner_ids).index_by(&:id)
      owner_ids.each do |owner_id|
        return owner_id if eligible?(users_by_id[owner_id])
      end
      nil
    end

    # Leads anteriores (não o atual) com corretor atribuído, aplicando match,
    # dono (atendido x qualquer atribuição) e janela de tempo.
    def base_scope
      scope = @lead.tenant.leads.where.not(id: @lead.id).where.not(admin_user_id: nil)

      scope = apply_match(scope)
      return nil if scope.nil?

      scope = scope.where(status: @setting.attended_status_values) if @setting.owner_attended_only?
      scope = scope.where("leads.updated_at >= ?", @setting.stickiness_window_days.to_i.days.ago) unless @setting.window_forever?
      scope
    end

    def apply_match(scope)
      ContactMatch.apply(scope, @lead, @setting.stickiness_match)
    end

    def eligible?(user)
      return false unless user&.active?

      if @setting.fallback_in_rule?
        candidate_ids.include?(user.id)
      else
        true
      end
    end

    def candidate_ids
      @candidate_ids ||= Array(@candidates).map(&:admin_user_id)
    end
  end
end

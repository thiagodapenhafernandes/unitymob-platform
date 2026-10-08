module Leads
  class ContingencyService
    def self.try_forward!(lead, rule:, reason:)
      Current.set(tenant: lead.tenant) do
        lead.with_lock { new(lead).try_forward!(rule, reason.to_s) }
      end
    end

    def self.default!(lead)
      Current.set(tenant: lead.tenant) do
        lead.with_lock do
          target = LeadSetting.instance(tenant: lead.tenant).default_distribution_rule
          target && new(lead).forward!(nil, target, "no_matching_rule")
        end
      end
    end

    def self.check!(lead)
      Current.set(tenant: lead.tenant) { lead.with_lock { new(lead).check! } }
    end

    def initialize(lead)
      @lead = lead
    end

    def check!
      return if Lead.non_operational_status_values(tenant: @lead.tenant).include?(@lead.status) || @lead.archived_at.present?
      if @lead.contingency_pending?
        return @lead.update!(contingency_pending: false) if @lead.admin_user_id.present?
        return deliver_to_target!
      end
      return if @lead.contingency_forwarded_at.present?
      return if @lead.admin_user_id.present? && Lead.status_value(@lead.status) != Lead.status_value(:waiting_acceptance)
      # Importações históricas não iniciam um ciclo operacional de distribuição.
      return if @lead.distribution_cycle_started_at.blank? && !@lead.activities.where(kind: "received").exists?

      rule = @lead.distribution_rule
      unless rule
        return unless @lead.admin_user_id.nil?
        return self.class.default!(@lead)
      end
      return unless rule.contingency_enabled?

      initialize_cycle!
      return try_forward!(rule, "deactivated") unless rule.active?
      if !rule.outside_represamento_hours? && rule.candidates_filtered_by_checkin.exists? && @lead.admin_user_id.nil? &&
          Lead.status_value(@lead.status) != Lead.status_value(:waiting_acceptance)
        return DistributorService.distribute_to(@lead, rule)
      end
      return true if rule.outside_represamento_hours? && try_forward!(rule, "outside_hours")
      return true if rule.candidates_filtered_by_checkin.empty? && try_forward!(rule, "unavailable")
      if Lead.status_value(@lead.status) == Lead.status_value(:waiting_acceptance)
        return true if try_forward!(rule, "acceptance_timeout")
        return true if @lead.admin_user_id.nil? && rule.pool_mode? && try_forward!(rule, "pool_timeout")
      end
      false
    end

    def try_forward!(rule, reason)
      return false unless forwardable? && rule.contingency_for?(reason)
      initialize_cycle!
      minutes = case reason
      when "unavailable" then rule.contingency_unavailable_minutes
      when "pool_timeout" then rule.contingency_pool_minutes
      when "acceptance_timeout" then rule.contingency_acceptance_minutes
      else 0
      end
      started_at = @lead.distribution_cycle_started_at
      if reason == "pool_timeout"
        started_at = @lead.activities.where(kind: %w[shark_tank_ready pocket_pool_ready])
          .where("created_at >= ?", started_at).minimum(:created_at) || started_at
      end
      return false if started_at + minutes.minutes > Time.current

      forward!(rule, rule.contingency_rule, reason)
    end

    def forward!(source, target, reason)
      return false unless forwardable?
      return false unless target && target.tenant_id == @lead.tenant_id && target.id != source&.id &&
        !target.contingency_enabled? && !target.attendance?

      initialize_cycle!
      previous_owner = @lead.admin_user
      previous_skip = @lead.skip_automatic_routing?
      previous_status = @lead.status
      @lead.skip_automatic_routing = true
      @lead.update!(admin_user: nil, status: Lead.default_status(tenant: @lead.tenant, pipeline: @lead.lead_pipeline),
        distribution_rule: target, contingency_source_rule: source, contingency_target_rule: target,
        contingency_forwarded_at: Time.current, contingency_reason: reason, contingency_pending: true)
      @lead.activities.create!(kind: "contingency_forwarded", metadata: {
        source_rule_id: source&.id, source_rule_name: source&.name, target_rule_id: target.id,
        target_rule_name: target.name, reason: reason, previous_admin_user_id: previous_owner&.id,
        cycle_started_at: @lead.distribution_cycle_started_at.iso8601
      }.compact)
      NotificationDispatcher.notify_lost_turn(@lead, previous_owner) if previous_owner
      deliver_to_target!
      if !previous_skip && previous_status != @lead.status
        Automation::Dispatcher.dispatch(:lead_stage_changed, @lead, source: "distribution",
          payload: { from: previous_status, to: @lead.status })
      end
      true
    ensure
      @lead.skip_automatic_routing = previous_skip unless previous_skip.nil?
    end

    private

    def forwardable?
      @lead.contingency_forwarded_at.blank? && @lead.archived_at.blank? &&
        !Lead.non_operational_status_values(tenant: @lead.tenant).include?(@lead.status) &&
        (@lead.admin_user_id.nil? || Lead.status_value(@lead.status) == Lead.status_value(:waiting_acceptance))
    end

    def initialize_cycle!
      return if @lead.distribution_cycle_started_at.present?
      started_at = @lead.activities.where(kind: "received").minimum(:created_at) || @lead.created_at
      @lead.update!(distribution_cycle_started_at: started_at)
    end

    def deliver_to_target!
      target = @lead.contingency_target_rule
      ready = target&.terminal_destination_for?(@lead.tenant) && !target.outside_represamento_hours? &&
        target.candidates_filtered_by_checkin.exists?
      if ready
        result = DistributorService.distribute_to(@lead, target)
        if @lead.admin_user_id.present? || (result && target.shark_tank?)
          @lead.update!(contingency_pending: false)
          return true
        end
      end
      @lead.update!(status: :represado) unless Lead.status_value(@lead.status) == Lead.status_value(:represado)
      # Um aviso por encaminhamento; tentativas periódicas não inundam a gestão.
      forwarding_id = @lead.activities.where(kind: "contingency_forwarded").order(id: :desc).pick(:id)
      unless @lead.activities.where(kind: "contingency_pending").where("metadata ->> 'forwarding_id' = ?", forwarding_id.to_s).exists?
        @lead.activities.create!(kind: "contingency_pending", metadata: {
          target_rule_id: target&.id, target_rule_name: target&.name, reason: "target_unavailable", forwarding_id: forwarding_id
        }.compact)
        @lead.tenant.admin_users.active.includes(:profile).each do |user|
          next unless user.tenant_owner? || user.can?(:manage, :distribution_rules)
          NotificationDispatcher.push_to(user, title: "Lead aguardando contingência",
            body: "A regra de destino não pode receber agora. Revise a disponibilidade dos responsáveis.",
            url: "/admin/leads/#{@lead.id}")
        end
      end
      false
    end
  end
end

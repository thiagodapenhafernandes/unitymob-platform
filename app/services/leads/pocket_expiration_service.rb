module Leads
  class PocketExpirationService
    def self.expire!(lead, expected_admin_user_id: nil, now: Time.current, source: "scheduled")
      new(lead, expected_admin_user_id: expected_admin_user_id, now: now, source: source).expire!
    end

    def initialize(lead, expected_admin_user_id: nil, now: Time.current, source: "scheduled")
      @lead = lead
      @expected_admin_user_id = expected_admin_user_id.presence&.to_i
      @now = now
      @source = source
    end

    def expire!
      return :not_found unless @lead

      previous_corretor = nil
      pool_ready = false
      result = nil

      @lead.with_lock do
        @lead.reload
        result = expiration_blocker

        if result.nil?
          previous_corretor = @lead.admin_user
          previous_admin_user_id = previous_corretor&.id

          pool_ready = @lead.distribution_rule&.pocket_to_pool?
          @lead.update!(status: pool_ready ? Lead.status_value(:waiting_acceptance) : Lead.default_status, admin_user_id: nil)
          @lead.activities.create!(
            kind: "pocket_expired",
            metadata: {
              previous_admin_user_id: previous_admin_user_id,
              previous_admin_user_name: previous_corretor&.name,
              distribution_rule_id: @lead.distribution_rule_id,
              source: @source,
              expired_at: @now.iso8601
            }.compact
          )
          if pool_ready
            @lead.activities.create!(
              kind: "pocket_pool_ready",
              metadata: {
                rule_id: @lead.distribution_rule_id,
                rule_name: @lead.distribution_rule&.name,
                previous_admin_user_id: previous_admin_user_id,
                previous_admin_user_name: previous_corretor&.name,
                source: @source,
                available_at: @now.iso8601
              }.compact
            )
          end

          result = :expired
        end
      end

      return result unless result == :expired

      Leads::NotificationDispatcher.notify_lost_turn(@lead.reload, previous_corretor)
      return notify_pool! if pool_ready

      Leads::RoutingService.new(@lead.reload).route!

      result
    end

    private

    def expiration_blocker
      return :not_waiting unless waiting_acceptance?
      return :unassigned if @lead.admin_user_id.blank?
      return :stale_assignment if stale_assignment?
      return :not_due unless due?

      nil
    end

    def waiting_acceptance?
      Lead.status_value(@lead.status) == Lead.status_value(:waiting_acceptance)
    end

    def stale_assignment?
      @expected_admin_user_id.present? && @lead.admin_user_id.to_i != @expected_admin_user_id
    end

    def due?
      rule = @lead.distribution_rule
      return false unless rule&.pocket_operational?

      assigned_at = current_assignment_at || @lead.updated_at || @lead.created_at
      assigned_at <= @now - rule.pocket_time.to_i.minutes
    end

    def current_assignment_at
      @lead.activities
           .where(kind: "distributed")
           .order(created_at: :desc)
           .limit(10)
           .detect { |activity| activity.meta("admin_user_id").to_i == @lead.admin_user_id.to_i }
           &.created_at
    end

    def notify_pool!
      lead = @lead.reload
      rule = lead.distribution_rule
      return :pool_ready unless rule

      Leads::NotificationDispatcher.notify_pool(lead, rule, candidates: rule.candidates_filtered_by_checkin, context: "pocket_pool")
      Leads::PoolRenotifyJob.set(wait: rule.pool_renotify_minutes_value.minutes).perform_later(lead.id, tenant_id: lead.tenant_id) if rule.pool_renotify_interval?
      :pool_ready
    end
  end
end

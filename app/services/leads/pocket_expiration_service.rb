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
      result = nil

      @lead.with_lock do
        @lead.reload
        result = expiration_blocker

        if result.nil?
          previous_corretor = @lead.admin_user
          previous_admin_user_id = previous_corretor&.id

          @lead.update!(status: Lead.default_status, admin_user_id: nil)
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

          result = :expired
        end
      end

      return result unless result == :expired

      Leads::NotificationDispatcher.notify_lost_turn(@lead.reload, previous_corretor)
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
  end
end

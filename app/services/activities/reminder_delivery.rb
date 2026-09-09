module Activities
  # Shared delivery state for tasks and appointments. Row locks serialize sends
  # with activity edits; the lead lock uses the same order as ownership changes.
  class ReminderDelivery
    SENT_EVENTS = %w[provider_accepted device_received].freeze

    def initialize(activity, setting:, now:)
      @activity, @setting, @now = activity, setting, now
      @kind = activity.is_a?(Task) ? "task" : "appointment"
    end

    def call(&delivery)
      lead = @activity.lead
      if lead
        lead.with_lock { deliver_locked(lead.id, &delivery) }
      else
        deliver_locked(nil, &delivery)
      end
    end

    private

    def deliver_locked(locked_lead_id)
      @activity.with_lock do
        # with_lock reloads the activity and its associations after any wait.
        next unless @activity.lead_id == locked_lead_id && eligible?
        @now = [@now, Time.current].max

        @scheduled_at = @activity.is_a?(Task) ? @activity.due_at : @activity.starts_at
        next unless @scheduled_at

        @state = current_state
        phase = current_phase
        if phase && !recent_attempt?(phase)
          @state["attempts"][phase] = @now.iso8601(6)
          begin
            sent = yield(phase, tag(phase))
            @state["sent"][phase] = [@now, Time.current].max.iso8601(6) if sent.to_i.positive?
          rescue StandardError => error
            Rails.error.report(error, handled: true, context: { activity_type: @kind, activity_id: @activity.id })
          end
        end
        @activity.update_columns(reminder_state: @state) if @activity.reminder_state != @state
      end
    end

    def eligible?
      return false unless @setting.tenant_id == @activity.tenant_id
      return false unless @activity.open_activity? && @activity.admin_user&.active?
      return false unless @activity.tenant_id == @activity.admin_user.tenant_id
      lead = @activity.lead
      if lead
        return false unless lead.tenant_id == @activity.tenant_id && lead.admin_user_id == @activity.admin_user_id
        if @activity.is_a?(Task)
          return false if Lead.non_operational_status_values(tenant: @activity.tenant).include?(Lead.status_value(lead.status, tenant: @activity.tenant))
          return false unless @activity.tenant.tasks.operational_current.exists?(@activity.id)
        end
      end
      return false if @activity.is_a?(Appointment) && @activity.habitation && @activity.habitation.tenant_id != @activity.tenant_id

      true
    end

    def current_state
      context = { "scheduled_at" => @scheduled_at.iso8601(6), "admin_user_id" => @activity.admin_user_id }
      previous = @activity.reminder_state
      if previous.empty? || previous.slice(*context.keys) == context
        state = previous.deep_dup.merge(context)
        state["sent"] ||= {}
        state["attempts"] ||= {}
        import_previous_events(state) unless state["initialized"]
      else
        state = context.merge("sent" => {}, "attempts" => {})
      end
      state.merge("initialized" => true)
    end

    # Existing deliveries survive rollout; rescheduling starts a fresh cycle.
    def import_previous_events(state)
      phases = (@setting.reminder_phases.keys + ["due"]).to_h { |phase| [legacy_tag(phase), phase] }
      events = PushDeliveryEvent.where(admin_user_id: @activity.admin_user_id)
      events.where(tag: phases.keys)
            .or(events.where("tag ~ ?", "^#{@kind}-overdue-#{@activity.id}-[0-9]+$"))
            .order(:created_at).pluck(:tag, :event_type, :created_at).each do |tag, event_type, created_at|
        phase = phases.fetch(tag, "overdue")
        state["attempts"][phase] = created_at.iso8601(6)
        state["sent"][phase] = created_at.iso8601(6) if SENT_EVENTS.include?(event_type)
      end
    end

    def current_phase
      if @scheduled_at > @now
        phase = @setting.reminder_phases.find { |_, duration| @scheduled_at <= @now + duration }&.first
        return phase unless @state["sent"].key?(phase)
        return nil
      end

      interval = @setting.reminder_overdue_minutes.minutes
      if @setting.reminder_due_enabled? && !@state["sent"].key?("due") && @scheduled_at > @now - interval
        return "due"
      end
      return unless @setting.reminder_business_hours?(@now)

      last_sent = %w[due overdue].filter_map { |phase| timestamp(@state["sent"][phase]) }.max
      return if (last_sent || @scheduled_at) > @now - interval

      "overdue"
    end

    def recent_attempt?(phase)
      # A new scheduled phase is not a retry. Due -> overdue, however, must
      # preserve the cooldown of a failed due delivery.
      phases = phase == "overdue" ? %w[due overdue] : [phase]
      phases.any? do |key|
        attempted_at = timestamp(@state["attempts"][key])
        sent_at = timestamp(@state["sent"][key])
        attempted_at && (!sent_at || sent_at < attempted_at) &&
          attempted_at > @now - @setting.reminder_retry_minutes.minutes
      end
    end

    def timestamp(value)
      Time.iso8601(value) if value
    end

    def legacy_tag(phase)
      return "task-return-#{@activity.id}" if @kind == "task" && phase == "due"

      "#{@kind}-#{phase}-#{@activity.id}"
    end

    def tag(phase)
      suffix = @scheduled_at.utc.strftime("%Y%m%d%H%M%S%6N")
      suffix += "-#{@now.to_i}" if phase == "overdue"
      "#{legacy_tag(phase)}-#{suffix}"
    end
  end
end

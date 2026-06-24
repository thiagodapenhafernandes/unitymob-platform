module Automation
  class EventBus
    def self.emit(name, lead:, source: "platform", payload: {}, idempotency_key: nil, async: true)
      new(
        name: name,
        lead: lead,
        source: source,
        payload: payload,
        idempotency_key: idempotency_key,
        async: async
      ).emit
    end

    def initialize(name:, lead:, source:, payload:, idempotency_key:, async:)
      @name = name.to_s
      @lead = lead
      @source = source.to_s.presence || "platform"
      @payload = payload.is_a?(Hash) ? payload : {}
      @idempotency_key = idempotency_key.to_s.presence
      @async = async
    end

    def emit
      return unless @lead

      event = find_or_build_event
      return event if event.persisted? && !event.pending?

      event.assign_attributes(
        lead: @lead,
        name: @name,
        source: @source,
        payload: @payload,
        occurred_at: Time.current
      )
      event.save!
      record_timeline(event)
      dispatch(event)
      event
    end

    private

    def find_or_build_event
      if @idempotency_key.present?
        AutomationEvent.find_or_initialize_by(idempotency_key: @idempotency_key)
      else
        AutomationEvent.new
      end
    end

    def record_timeline(event)
      LeadActivity.log!(
        lead: @lead,
        kind: "automation_event",
        metadata: {
          automation_event_id: event.id,
          event: event.name,
          label: event.name_label,
          source: event.source
        }
      )
    end

    def dispatch(event)
      if @async
        Automation::ProcessEventJob.perform_later(event.id)
      else
        Automation::ProcessEventJob.perform_now(event.id)
      end
    end
  end
end

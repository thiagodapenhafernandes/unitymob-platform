module Automation
  class EventOperator
    def self.reprocess!(event, by: nil)
      new(event, by: by).reprocess!
    end

    def self.ignore!(event, reason:, by: nil)
      new(event, by: by).ignore!(reason: reason)
    end

    def initialize(event, by: nil)
      @event = event
      @by = by
    end

    def reprocess!
      raise ArgumentError, "evento sem lead vinculado" unless @event&.lead
      raise ArgumentError, "apenas eventos com erro podem ser reprocessados" unless @event.reprocessable?

      @event.update!(
        status: "pending",
        processed_at: nil,
        error_message: nil,
        payload: @event.payload_hash.merge(
          reprocessed_at: Time.current.iso8601,
          reprocessed_by: @by&.name
        ).compact
      )
      Automation::ProcessEventJob.perform_later(@event.id)
      LeadActivity.log!(lead: @event.lead, kind: "automation_event", metadata: {
        automation_event_id: @event.id,
        event: @event.name,
        action: "reprocess",
        by: @by&.name
      }.compact)
      @event
    end

    def ignore!(reason:)
      reason = reason.to_s.strip
      raise ArgumentError, "informe o motivo para ignorar o evento" if reason.blank?

      @event.update!(
        status: "ignored",
        processed_at: Time.current,
        error_message: nil,
        payload: @event.payload_hash.merge(
          ignored_reason: reason,
          ignored_at: Time.current.iso8601,
          ignored_by: @by&.name
        ).compact
      )
      LeadActivity.log!(lead: @event.lead, kind: "automation_event", metadata: {
        automation_event_id: @event.id,
        event: @event.name,
        action: "ignore",
        reason: reason,
        by: @by&.name
      }.compact) if @event.lead
      @event
    end
  end
end

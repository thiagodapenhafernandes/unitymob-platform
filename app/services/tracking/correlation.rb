module Tracking
  class Correlation
    def self.lead_created(lead)
      context(lead, key: "lead:#{lead.id}:created", name: "lead_created", at: lead.created_at)
    end

    def self.change(record)
      lead = record.is_a?(Lead) ? record : record.lead
      changes = Digest::SHA256.hexdigest(ActiveSupport::JSON.encode(record.saved_changes.sort.to_h))
      context(lead, key: "#{record.class.model_name.singular}:#{record.id}:#{record.updated_at.utc.iso8601(6)}:#{changes}",
        name: "#{record.class.model_name.singular}_updated", at: record.updated_at)
    end

    def self.submission(submission)
      { tenant_id: submission.tenant_id, public_form_submission_id: submission.id,
        occurrence_key: "public_form_submission:#{submission.id}", occurrence_name: "form_submitted",
        occurred_at: submission.created_at.iso8601(6) }
    end

    def self.webhook(tenant:, event_name:, data:)
      return unless tenant

      safely do
        values = data.to_h.with_indifferent_access
        lead = tenant.leads.find_by(id: values[:id]) if values[:tenant_id].to_s == tenant.id.to_s
        if lead && event_name == "lead_created"
          lead_created(lead)
        else
          { tenant_id: tenant.id, lead_id: lead&.id, occurrence_key: "webhook:#{SecureRandom.uuid}",
            occurrence_name: event_name, occurred_at: Time.current.iso8601(6) }
        end
      end
    end

    def self.record(context, transport:, event_id:, destination:, status: "pending", native_event: nil)
      return unless context

      safely do
        attributes = context.symbolize_keys
        TrackingEventLink.create_or_find_by!(tenant_id: attributes.fetch(:tenant_id), transport: transport,
          external_event_id: event_id, destination_key: destination_key(destination)) do |link|
          link.assign_attributes(attributes.except(:tenant_id))
          link.destination_label = %w[webhook google_webhook].include?(transport) ? URI.parse(destination).host : destination
          link.status = status
          link.google_stage_conversion_event = native_event if transport == "google_webhook"
          link.ga4_conversion_event = native_event if transport == "ga4"
        end
      end
    end

    def self.attempt(link, status:, http_status: nil, error_class: nil, trace_id: nil, reason: nil, occurrence_key: nil)
      return unless link

      safely do
        link.with_lock do
          entry = { "at" => Time.current.iso8601(6), "status" => status, "http_status" => http_status,
            "error_class" => error_class, "trace_id" => (trace_id.first(128) if trace_id.is_a?(String)), "reason" => reason,
            "occurrence_key" => occurrence_key || link.occurrence_key }.compact
          link.update!(status: link.status == "received" ? "received" : status, attempt_log: link.attempt_log + [entry])
        end
      end
    end

    def self.webhook_attempt(reference, url:, event_id:, **result)
      return unless reference

      safely do
        reference = reference.with_indifferent_access
        link = TrackingEventLink.find_by(tenant_id: reference[:tenant_id], id: reference[:id],
          transport: "webhook", external_event_id: event_id, destination_key: destination_key(url))
        attempt(link, **result)
      end
    end

    def self.link_submission(submission)
      return unless submission.lead && submission.lead.tenant_id == submission.tenant_id

      safely do
        TrackingEventLink.where(tenant_id: submission.tenant_id, public_form_submission_id: submission.id)
          .where(lead_id: nil).update_all(lead_id: submission.lead_id, updated_at: Time.current)
      end
    end

    def self.skip_meta(context, tenant_id:, lead_id:, event_id:, reason:)
      return unless context

      safely do
        context = context.with_indifferent_access
        next unless context[:tenant_id].to_i == tenant_id && context[:lead_id].to_i == lead_id

        TrackingEventLink.where(tenant_id: tenant_id, lead_id: lead_id,
          transport: "meta", external_event_id: event_id).find_each do |link|
          attempt(link, status: "skipped", reason: reason, occurrence_key: context[:occurrence_key])
        end
      end
    end

    def self.destination_key(destination)
      Digest::SHA256.hexdigest(destination.to_s)
    end

    def self.context(lead, key:, name:, at:)
      { tenant_id: lead.tenant_id, lead_id: lead.id, occurrence_key: key, occurrence_name: name, occurred_at: at.iso8601(6) }
    end
    private_class_method :context

    def self.safely
      TrackingEventLink.transaction(requires_new: true) { yield }
    rescue StandardError => error
      Rails.logger.warn("[TRACKING_CORRELATION] error_class=#{error.class.name}")
      nil
    end
    private_class_method :safely
  end
end

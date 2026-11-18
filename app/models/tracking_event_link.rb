class TrackingEventLink < ApplicationRecord
  include TenantScoped

  TRANSPORTS = %w[site webhook google_webhook ga4 meta].freeze
  STATUSES = %w[pending browser_offered http_accepted received failed uncertain skipped].freeze

  belongs_to :lead, optional: true
  belongs_to :public_form_submission, optional: true
  belongs_to :google_stage_conversion_event, optional: true
  belongs_to :ga4_conversion_event, optional: true

  validates :occurrence_key, :occurrence_name, :occurred_at, :external_event_id,
    :destination_key, :destination_label, presence: true
  validates :transport, inclusion: { in: TRANSPORTS }
  validates :status, inclusion: { in: STATUSES }
  validate :same_tenant

  def delivery_status
    if transport == "google_webhook"
      value = google_stage_conversion_event&.status || "record_removed"
      value == "delivered" ? "http_accepted" : value
    elsif transport == "ga4"
      ga4_conversion_event&.status || "record_removed"
    else
      status
    end
  end

  def delivery_skip_reason
    return google_stage_conversion_event&.skip_reason if transport == "google_webhook"
    return ga4_conversion_event&.skip_reason if transport == "ga4"

    attempt_log.last&.fetch("reason", nil) if status == "skipped"
  end

  def delivery_attempts
    return google_stage_conversion_event&.attempt_log || [] if transport == "google_webhook"
    if transport == "ga4"
      event = ga4_conversion_event
      return [] unless event&.attempted_at

      return [{ "at" => event.attempted_at.iso8601, "http_status" => event.http_status }.compact]
    end
    attempt_log
  end

  private

  def same_tenant
    %i[lead public_form_submission google_stage_conversion_event ga4_conversion_event].each do |name|
      record = public_send(name)
      errors.add(name, "deve pertencer à mesma conta") if record && record.tenant_id != tenant_id
    end
    [google_stage_conversion_event, ga4_conversion_event].compact.each do |event|
      errors.add(:lead, "deve corresponder ao evento de conversão") if lead_id && event.lead_id != lead_id
    end
  end
end

class Ga4ConversionEvent < ApplicationRecord
  include TenantScoped

  EVENTS = %w[qualify_lead visit_completed proposal_sent close_convert_lead].freeze
  STATUSES = %w[pending sending http_accepted rejected uncertain skipped].freeze
  PARAMETER_KEYS = %w[business_type property_code event_id lead_source].freeze

  belongs_to :lead
  encrypts :client_id

  validates :event_name, inclusion: { in: EVENTS }
  validates :status, inclusion: { in: STATUSES }
  validates :deduplication_key, :event_id, :measurement_id, :occurred_at, presence: true
  validates :client_id, format: { with: /\A\d{1,20}\.\d{1,20}\z/ }
  validate :safe_parameters
  validate :lead_belongs_to_tenant

  after_create_commit :enqueue_delivery

  def measurement_payload
    {
      client_id: client_id,
      timestamp_micros: (occurred_at.to_r * 1_000_000).to_i,
      consent: { ad_user_data: "DENIED", ad_personalization: "DENIED" },
      events: [{ name: event_name, params: parameters.slice(*PARAMETER_KEYS) }]
    }
  end

  private

  def safe_parameters
    errors.add(:parameters, "contém campos não permitidos") unless parameters.is_a?(Hash) && (parameters.keys - PARAMETER_KEYS).empty?
  end

  def lead_belongs_to_tenant
    errors.add(:lead, "deve pertencer à mesma conta") if lead && lead.tenant_id != tenant_id
  end

  def enqueue_delivery
    Ga4ConversionDeliveryJob.perform_later(tenant_id, id)
  rescue StandardError => error
    Rails.logger.warn("[GA4_CRM] enqueue_failed event_id=#{event_id} error_class=#{error.class.name}")
  end
end

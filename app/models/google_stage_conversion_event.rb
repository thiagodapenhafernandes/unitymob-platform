class GoogleStageConversionEvent < ApplicationRecord
  include TenantScoped
  belongs_to :lead
  belongs_to :webhook_setting, optional: true
  encrypts :payload, :destination_url

  validates :conversion_type, inclusion: { in: %w[qualificado visita proposta fechamento] }
  validates :status, inclusion: { in: %w[pending delivered failed skipped] }
  validates :payload, :destination_url, :occurred_at, presence: true
  validate :same_tenant
  after_create_commit :enqueue_delivery

  def payload_data
    JSON.parse(payload)
  end

  def enqueue_delivery
    return unless status == "pending"

    GoogleStageConversionDeliveryJob.set(wait_until: next_attempt_at || Time.current).perform_later(tenant_id, id)
  rescue StandardError => error
    Rails.logger.warn("[GOOGLE_STAGE] enqueue_failed tenant_id=#{tenant_id} event_id=#{id} error_class=#{error.class.name}")
  end

  private

  def same_tenant
    errors.add(:lead, "deve pertencer à mesma conta") if lead && lead.tenant_id != tenant_id
    errors.add(:webhook_setting, "deve pertencer à mesma conta") if webhook_setting && webhook_setting.tenant_id != tenant_id
  end
end

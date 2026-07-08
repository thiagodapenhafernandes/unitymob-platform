class WhatsappSenderNumber < ApplicationRecord
  include TenantScoped

  STATUSES = %w[connected pending failed disconnected].freeze

  belongs_to :whatsapp_business_integration, optional: true
  has_many :whatsapp_campaigns, dependent: :restrict_with_error
  has_many :whatsapp_campaign_unsubscribes, dependent: :restrict_with_error

  validates :label, :display_phone_number, :phone_number_id, presence: true
  validates :phone_number_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :cpl_sent_unit_price,
            :cpl_fla_unit_price,
            numericality: { greater_than_or_equal_to: 0, less_than: 1_000_000 }
  validate :display_phone_number_must_be_valid
  validate :integration_must_belong_to_tenant
  before_save :clear_other_notification_sender, if: :active_notification_sender?

  scope :active, -> { where(active: true) }
  scope :for_notifications, -> { where(use_for_notifications: true) }
  scope :ordered, -> { order(active: :desc, label: :asc, display_phone_number: :asc) }

  def self.default_for_campaign(tenant = Current.tenant)
    raise ArgumentError, "Tenant obrigatório para número de envio WhatsApp" if tenant.blank?

    tenant.whatsapp_sender_numbers.active.ordered.first || sync_from_current_integration!(tenant)
  end

  def self.default_for_notifications(tenant = Current.tenant)
    raise ArgumentError, "Tenant obrigatório para número de notificação WhatsApp" if tenant.blank?

    tenant.whatsapp_sender_numbers.active.for_notifications.ordered.first
  end

  def self.sync_from_current_integration!(tenant = Current.tenant)
    raise ArgumentError, "Tenant obrigatório para sincronizar número de envio WhatsApp" if tenant.blank?

    integration = WhatsappBusinessIntegration.current(tenant)
    return nil unless integration.phone_number_id.present?

    tenant.whatsapp_sender_numbers.find_or_create_by!(phone_number_id: integration.phone_number_id) do |number|
      number.whatsapp_business_integration = integration if integration.persisted?
      number.waba_id = integration.waba_id
      number.display_phone_number = integration.default_whatsapp_number.presence || integration.phone_number_id
      number.verified_name = "WhatsApp principal"
      number.label = number.verified_name
      number.status = integration.messaging_ready? ? "connected" : "pending"
      number.active = true
      number.use_for_notifications = false if number.has_attribute?(:use_for_notifications)
    end
  end

  def access_token
    whatsapp_business_integration&.access_token || WhatsappBusinessIntegration.current(tenant).access_token
  end

  def messaging_ready?
    active? && access_token.present? && phone_number_id.present?
  end

  def display_label
    [label, formatted_phone].compact_blank.join(" · ")
  end

  def formatted_phone
    display_phone_number.presence
  end

  def campaign_cost(sent_count:, failed_count:)
    (sent_count.to_i * cpl_sent_unit_price.to_d) + (failed_count.to_i * cpl_fla_unit_price.to_d)
  end

  private

  def display_phone_number_must_be_valid
    digits = display_phone_number.to_s.gsub(/\D/, "")
    return if digits.length.between?(10, 15)

    errors.add(:display_phone_number, "deve ter DDD e número válidos")
  end

  def integration_must_belong_to_tenant
    return if whatsapp_business_integration.blank? || tenant_id.blank?
    return if whatsapp_business_integration.tenant_id == tenant_id

    errors.add(:whatsapp_business_integration, "deve pertencer ao mesmo Tenant")
  end

  def active_notification_sender?
    active? && use_for_notifications?
  end

  def clear_other_notification_sender
    return if tenant_id.blank?

    self.class
      .where(tenant_id: tenant_id, use_for_notifications: true)
      .where.not(id: id)
      .update_all(use_for_notifications: false, updated_at: Time.current)
  end
end

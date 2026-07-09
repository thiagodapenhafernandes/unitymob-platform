class WhatsappCampaignUnsubscribe < ApplicationRecord
  include TenantScoped

  SOURCES = %w[campaign_button manual backfill].freeze

  belongs_to :whatsapp_sender_number
  belongs_to :whatsapp_campaign, optional: true
  belongs_to :whatsapp_campaign_message, optional: true
  belongs_to :whatsapp_campaign_recipient, optional: true
  belongs_to :unsubscribed_by_message, class_name: "WhatsappMessage", optional: true
  belongs_to :reenabled_by, class_name: "AdminUser", optional: true

  validates :phone_number, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :reason, presence: true
  validates :unsubscribed_at, presence: true
  validate :active_phone_must_be_unique, unless: :reenabled?

  before_validation :normalize_phone_number
  before_validation :set_defaults

  scope :active, -> { where(reenabled_at: nil) }
  scope :reenabled, -> { where.not(reenabled_at: nil) }
  scope :recent, -> { order(unsubscribed_at: :desc, id: :desc) }

  def self.active_for?(sender_number:, phone:)
    return false if sender_number.blank?

    active.exists?(whatsapp_sender_number: sender_number, phone_number: Phones::Normalizer.call(phone).to_s)
  end

  def self.register!(sender_number:, phone:, contact_name: nil, campaign_message: nil, campaign_recipient: nil, inbound_message: nil, source: "campaign_button", reason: nil, metadata: {})
    normalized_phone = Phones::Normalizer.call(phone).to_s
    record = active.find_or_initialize_by(whatsapp_sender_number: sender_number, phone_number: normalized_phone)
    record.assign_attributes(
      whatsapp_campaign: campaign_message&.whatsapp_campaign || campaign_recipient&.whatsapp_campaign || record.whatsapp_campaign,
      whatsapp_campaign_message: campaign_message || record.whatsapp_campaign_message,
      whatsapp_campaign_recipient: campaign_recipient || record.whatsapp_campaign_recipient,
      unsubscribed_by_message: inbound_message || record.unsubscribed_by_message,
      contact_name: contact_name.presence || campaign_recipient&.display_name || record.contact_name,
      source: source,
      reason: reason.presence || "Descadastro solicitado pelo contato.",
      unsubscribed_at: record.unsubscribed_at || Time.current,
      metadata: record.metadata.to_h.merge(metadata.to_h)
    )
    record.save!
    record
  end

  def reenabled?
    reenabled_at.present?
  end

  def reenable!(admin_user:, reason: nil)
    update!(
      reenabled_by: admin_user,
      reenabled_at: Time.current,
      reenable_reason: reason.to_s.strip.presence
    )
  end

  private

  def normalize_phone_number
    self.phone_number = Phones::Normalizer.call(phone_number).to_s
  end

  def set_defaults
    self.source = "campaign_button" if source.blank?
    self.reason = "Descadastro solicitado pelo contato." if reason.blank?
    self.unsubscribed_at ||= Time.current
    self.metadata = {} unless metadata.is_a?(Hash)
  end

  def active_phone_must_be_unique
    return if whatsapp_sender_number_id.blank? || phone_number.blank?

    duplicate = self.class.active
      .where(whatsapp_sender_number_id: whatsapp_sender_number_id, phone_number: phone_number)
      .where.not(id: id)
      .exists?
    errors.add(:phone_number, "já está descadastrado para este número") if duplicate
  end
end

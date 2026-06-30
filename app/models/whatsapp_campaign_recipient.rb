class WhatsappCampaignRecipient < ApplicationRecord
  include TenantScoped

  SOURCES = %w[spreadsheet filters saved_audience manual].freeze
  CONVERSION_STATUSES = %w[pending converted no_interest unsubscribed ignored].freeze

  belongs_to :whatsapp_campaign
  belongs_to :lead, optional: true
  belongs_to :admin_user, optional: true
  has_many :campaign_messages,
           class_name: "WhatsappCampaignMessage",
           dependent: :nullify,
           inverse_of: :whatsapp_campaign_recipient

  validates :phone_number, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :conversion_status, inclusion: { in: CONVERSION_STATUSES }

  before_validation :normalize_phone_number
  before_validation :normalize_tags
  before_validation :set_defaults

  def display_name
    lead&.display_name.presence || name.presence || "Contato #{display_phone}"
  end

  def display_phone
    lead&.display_phone.presence || phone_number
  end

  def display_email
    lead&.display_email.presence || email
  end

  def tag_list
    Lead.normalize_tags_value(tags)
  end

  def converted?
    conversion_status == "converted" && lead_id.present?
  end

  def convert_to_lead!(distribution_rule: nil, status: nil, origin: nil)
    return lead if lead.present?

    created_lead = Lead.new(
      tenant: tenant,
      name: display_name,
      phone: display_phone,
      email: display_email,
      origin: origin.presence || self.origin.presence || "whatsapp_campaign",
      status: status.presence || Lead.default_status,
      tags: tag_list,
      admin_user_id: admin_user_id,
      distribution_rule: distribution_rule
    )
    created_lead.save!

    update!(
      lead: created_lead,
      conversion_status: "converted",
      converted_at: Time.current
    )
    created_lead
  end

  def mark_no_interest!
    update!(conversion_status: "no_interest")
  end

  def unsubscribe!
    update!(conversion_status: "unsubscribed", unsubscribed_at: Time.current)
  end

  private

  def normalize_phone_number
    digits = phone_number.to_s.gsub(/\D/, "")
    return self.phone_number = "" if digits.blank?

    self.phone_number = digits.length <= 11 ? "55#{digits}" : digits
  end

  def normalize_tags
    self.tags = Lead.normalize_tags_value(tags)
  end

  def set_defaults
    self.source = "spreadsheet" if source.blank?
    self.origin = "whatsapp_campaign" if origin.blank?
    self.status = Lead.default_status(tenant: tenant || whatsapp_campaign&.tenant || Current.tenant) if status.blank?
    self.conversion_status = "pending" if conversion_status.blank?
    self.custom_data = {} unless custom_data.is_a?(Hash)
  end
end

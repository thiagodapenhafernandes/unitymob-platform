class WhatsappConversation < ApplicationRecord
  belongs_to :lead, optional: true
  belongs_to :assigned_admin_user, class_name: "AdminUser", optional: true
  has_many :messages, -> { order(:created_at) }, class_name: "WhatsappMessage", dependent: :destroy

  validates :contact_phone, presence: true, uniqueness: true

  scope :open, -> { where(status: "open") }
  scope :recent, -> { order(Arel.sql("last_message_at DESC NULLS LAST, updated_at DESC")) }
  scope :unread, -> { where("unread_count > 0") }

  def display_name
    contact_name.presence || lead&.display_name.presence || contact_phone
  end

  def mark_read!
    update_columns(unread_count: 0, updated_at: Time.current) if unread_count.to_i.positive?
  end

  def touch_last_message!(message)
    update_columns(
      last_message_at: message.created_at,
      last_message_preview: message.preview,
      updated_at: Time.current
    )
  end

  def whatsapp_link
    digits = contact_phone.to_s.gsub(/\D/, "")
    "https://wa.me/#{digits}"
  end
end

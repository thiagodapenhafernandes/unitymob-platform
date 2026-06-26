class WhatsappConversation < ApplicationRecord
  belongs_to :lead, optional: true
  belongs_to :assigned_admin_user, class_name: "AdminUser", optional: true
  has_many :messages, -> { order(:created_at) }, class_name: "WhatsappMessage", dependent: :destroy

  validates :contact_phone, uniqueness: true, allow_nil: true
  validates :business_scoped_user_id, uniqueness: true, allow_nil: true
  # Toda conversa precisa de pelo menos uma identidade (telefone ou BSUID).
  validate :phone_or_bsuid_present

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
    return if digits.blank? # sem telefone (só BSUID) não há link wa.me

    "https://wa.me/#{digits}"
  end

  # Destinatário para a Cloud API: telefone se houver, senão BSUID.
  def cloud_recipient
    return contact_phone if contact_phone.present?
    return { user_id: business_scoped_user_id } if business_scoped_user_id.present?

    nil
  end

  private

  def phone_or_bsuid_present
    return if contact_phone.present? || business_scoped_user_id.present?

    errors.add(:base, "Conversa precisa de telefone ou BSUID")
  end
end

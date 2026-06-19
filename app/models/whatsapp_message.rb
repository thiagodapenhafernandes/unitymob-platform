class WhatsappMessage < ApplicationRecord
  belongs_to :whatsapp_conversation
  belongs_to :admin_user, optional: true

  DIRECTIONS = %w[inbound outbound].freeze
  STATUSES = %w[pending sent delivered read failed].freeze

  validates :direction, inclusion: { in: DIRECTIONS }

  scope :ordered, -> { order(:created_at) }
  scope :inbound, -> { where(direction: "inbound") }
  scope :outbound, -> { where(direction: "outbound") }

  def inbound? = direction == "inbound"
  def outbound? = direction == "outbound"
  def failed? = status == "failed"

  def preview
    case msg_type
    when "text" then body.to_s.truncate(80)
    when "template" then "[modelo] #{template_name}"
    when "image" then "[imagem]"
    when "document" then "[documento]"
    when "audio" then "[áudio]"
    else body.presence || "[#{msg_type}]"
    end
  end
end

class WhatsappMessage < ApplicationRecord
  include TenantScoped

  belongs_to :whatsapp_conversation
  belongs_to :admin_user, optional: true
  # Carimbo de origem: presente quando a mensagem veio de um cartão de
  # apresentação (auditoria consultável, com ou sem lead).
  belongs_to :presentation_card, optional: true
  has_one_attached :media_file

  DIRECTIONS = %w[inbound outbound].freeze
  STATUSES = %w[pending sent delivered read failed].freeze

  validates :direction, inclusion: { in: DIRECTIONS }

  scope :ordered, -> { order(:created_at) }
  scope :inbound, -> { where(direction: "inbound") }
  scope :outbound, -> { where(direction: "outbound") }

  def inbound? = direction == "inbound"
  def outbound? = direction == "outbound"
  def failed? = status == "failed"
  def media? = %w[image document audio video].include?(msg_type.to_s)
  def image? = msg_type == "image"
  def document? = msg_type == "document"
  def audio? = msg_type == "audio"
  def video? = msg_type == "video"
  def attachment_present? = media_file.attached?
  def service_window_closed_failure?
    failed? && outbound? && Whatsapp::SendFailureClassifier.service_window_closed?(error_message: error_message)
  end

  def presentation_avatar_attachment
    return unless image? && presentation_card_id.present?

    avatar = admin_user&.avatar
    avatar if avatar&.attached?
  end

  # "Apagar para mim": mensagens ocultas somem do thread do CRM
  scope :visible, -> { column_names.include?("hidden_at") ? where(hidden_at: nil) : all }

  # Mensagem citada (menu Responder) — resolvida dentro da mesma conversa
  def replied_message
    return nil if try(:context_wa_message_id).blank?

    @replied_message ||= whatsapp_conversation.messages.find_by(wa_message_id: context_wa_message_id)
  end

  def media_name
    media_file.attached? ? media_file.filename.to_s : template_name.presence
  end

  def media_source
    media_url.presence
  end

  def media_content_type
    media_file.attached? ? media_file.content_type.to_s : nil
  end

  def media_format_label
    extension = File.extname(media_name.to_s).delete_prefix(".").upcase
    return extension if extension.present?

    Whatsapp::MediaSupport.short_label_for_content_type(media_content_type)
  end

  def media_size_label
    return unless media_file.attached?

    ActiveSupport::NumberHelper.number_to_human_size(media_file.byte_size)
  end

  def media_inline?
    image? || video? || audio?
  end

  def preview
    case msg_type
    when "text" then body.to_s.truncate(80)
    when "template" then "[modelo] #{template_name}"
    when "image" then "[imagem]"
    when "document" then "[documento]"
    when "audio" then "[áudio]"
    when "video" then "[vídeo]"
    else body.presence || "[#{msg_type}]"
    end
  end

  def template_footer_text
    return unless msg_type == "template" && template_name.present?

    tenant.whatsapp_templates
          .where(name: template_name)
          .order(Arel.sql("CASE WHEN status = 'APPROVED' THEN 0 ELSE 1 END"), updated_at: :desc)
          .pick(:footer_text)
  end
end

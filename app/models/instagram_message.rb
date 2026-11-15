class InstagramMessage < ApplicationRecord
  belongs_to :lead
  belongs_to :sent_by_admin_user, class_name: "AdminUser", optional: true

  after_create_commit :notify_conversation
  after_create_commit :enqueue_ad_enrichment
  after_create_commit :record_property_journey

  validates :message_id, :occurred_at, presence: true
  validates :direction, inclusion: { in: %w[inbound outbound] }

  scope :inbound, -> { where(direction: "inbound") }
  scope :outbound, -> { where(direction: "outbound") }
  scope :chronological, -> { order(:occurred_at, :id) }

  def inbound? = direction == "inbound"

  def outbound? = direction == "outbound"

  def self.received_context(message)
    context = {}
    reply = message["reply_to"].is_a?(Hash) ? message["reply_to"] : {}
    story = reply["story"]
    if story.is_a?(Hash)
      context["story_id"] = story["id"].to_s.first(200) if story["id"].present?
      context["story_url"] = safe_media_url(story["url"])
    end
    context["reply_to_message_id"] = reply["mid"].to_s.first(1000) if reply["mid"].present?
    context["attachments"] = Array(message["attachments"]).first(10).filter_map do |attachment|
      next unless attachment.is_a?(Hash)
      payload = attachment["payload"].is_a?(Hash) ? attachment["payload"] : {}
      {"type" => attachment["type"].to_s.first(100), "url" => safe_media_url(payload["url"]),
        "title" => payload["title"].to_s.first(20_000), "media_id" => (payload["ig_post_media_id"] || payload["id"]).to_s.first(200)}.compact_blank
    end
    context.compact_blank
  end

  def self.safe_media_url(value)
    return unless value.is_a?(String) && value.length <= 16_000
    uri = URI.parse(value)
    value if uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    nil
  end

  def self.property_codes_in(text)
    codes = text.to_s.scan(/\b(?:c[oó]d(?:igo)?|ref(?:er[eê]ncia)?)\s*[.:#-]?\s*([\p{L}\d-]+)/i).flatten
    codes << text.to_s.strip if text.to_s.strip.match?(/\A[\p{L}\d-]{1,40}\z/) && !Instagram::CaptureAnswer.new(text).phone
    codes.select { |code| code.match?(/\d/) }.uniq
  end

  def property_reference_codes
    explicit = self.class.property_codes_in(body)
    return explicit if explicit.any?

    Array(context.to_h["attachments"]).flat_map { |attachment| self.class.property_codes_in(attachment["title"]) }.uniq
  end

  def contextual_interaction?
    context.to_h["story_id"].present? || context.to_h["attachments"].present?
  end

  def automation_input?
    return true if context.to_h.dig("referral", "ad_id").present?
    return false unless body.to_s.match?(/[\p{L}\d]/)
    return true unless contextual_interaction?

    answer = Instagram::CaptureAnswer.new(body)
    answer.request? || answer.phone.present? || answer.name(explicit_only: true).present? || answer.business_type.present?
  end

  def context_description
    parts = []
    parts << "Resposta a story" if context.to_h["story_id"].present?
    Array(context.to_h["attachments"]).each do |attachment|
      label = case attachment["type"]
      when "story_mention" then "Mencionou a conta em um story"
      when "story", "ig_story" then "Compartilhou um story"
      when "share", "ig_post", "ig_reel", "reel" then "Compartilhou uma publicação"
      when "image" then "Enviou uma imagem"
      when "video" then "Enviou um vídeo"
      when "audio" then "Enviou um áudio"
      else "Enviou um anexo"
      end
      parts << [label, attachment["title"].presence].compact.join(": ")
    end
    parts.uniq.join("; ")
  end

  def media_items
    items = []
    items << { "type" => "auto", "url" => context.to_h["story_url"] } if context.to_h["story_url"].present?
    items.concat(Array(context.to_h["attachments"]))
    items.filter_map do |item|
      url = self.class.safe_media_url(item["url"])
      next unless url
      kind = case item["type"]
      when "image", "video", "audio" then item["type"]
      when "ig_reel", "reel" then "video"
      when "auto", "story", "ig_story", "story_mention", "ig_post", "share" then "auto"
      else "document"
      end
      { kind: kind, url: url }
    end.uniq { |item| item[:url] }
  end

  def media_urls
    media_items.pluck(:url)
  end

  def conversation_text
    [body.presence, context_description.presence].compact.join("\n")
  end

  private

  def record_property_journey
    Instagram::PropertyJourney.record_message(self)
  rescue StandardError => error
    Rails.logger.warn("[Instagram journey] record unavailable message_id=#{id} class=#{error.class}")
  end

  def enqueue_ad_enrichment
    referral = context.to_h["referral"]
    return unless inbound? && context.to_h["meta_facebook_page_id"].present? && referral.is_a?(Hash) && referral["ad_id"].present?

    Instagram::AdEnrichmentJob.perform_later(lead.tenant_id, lead.id, id)
  rescue StandardError => error
    Rails.logger.warn("[Instagram ad enrichment] enqueue unavailable class=#{error.class}")
  end

  def notify_unread
    user = lead.admin_user
    if user.nil?
      integration = UserMetaIntegration.owned_by_tenant(lead.tenant_id).joins(:meta_facebook_pages)
        .find_by(meta_facebook_pages: { instagram_id: lead.instagram_account_id, instagram_enabled: true })
      user = integration&.admin_user
    end
    return unless user&.active? && user.tenant_id == lead.tenant_id && user.can?(:view, :leads)
    return unless Lead.accessible_to_admin(user, tenant: lead.tenant).exists?(id: lead.id)

    previous_direction = lead.instagram_messages.where("occurred_at < ? OR (occurred_at = ? AND id < ?)", occurred_at, occurred_at, id)
      .order(occurred_at: :desc, id: :desc).pick(:direction)
    notification = InAppNotification.notify!(admin_user: user, kind: "instagram_message", title: "Nova mensagem para #{lead.display_name}", body: conversation_text.presence&.truncate(160),
      url: Rails.application.routes.url_helpers.admin_lead_path(lead, anchor: "lead-instagram-thread"),
      metadata: { lead_id: lead.id, instagram_message_id: id, sender_name: lead.display_name,
        event: (previous_direction == "outbound" ? "message_reply" : "instagram_message") })
    if notification && lead.admin_user_id == user.id
      Notifications::PushDeliveryJob.perform_later(admin_user_id: user.id, title: notification.title,
        body: notification.body.to_s, url: notification.url, lead_id: lead.id, notification_context: "instagram_message")
    end
  rescue StandardError => error
    Rails.logger.warn("[Instagram unread] notification unavailable class=#{error.class}")
  end

  def notify_conversation
    notify_unread if inbound?
    ActionCable.server.broadcast(LeadConversationChannel.stream_name(lead), { refresh: true })
  rescue StandardError => error
    Rails.logger.warn("[Instagram thread] broadcast unavailable class=#{error.class}")
  end
end

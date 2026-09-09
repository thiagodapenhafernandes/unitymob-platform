module Admin::WhatsappTemplatesHelper
  def whatsapp_preview_text(text)
    escaped = ERB::Util.html_escape(text.to_s)
    escaped = escaped.gsub(/\*([^*\n]+)\*/, '<strong>\1</strong>')
      .gsub(/~([^~\n]+)~/, '<del>\1</del>')
      .gsub(/_([^_\n]+)_/, '<em>\1</em>')
    simple_format(escaped, {}, sanitize: true)
  end

  def whatsapp_preview_media_url(attachment, handle)
    return url_for(attachment) if attachment&.attached?

    uri = URI.parse(handle.to_s)
    uri.to_s if uri.is_a?(URI::HTTPS) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end
end

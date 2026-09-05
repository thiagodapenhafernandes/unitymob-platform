module Support::MessagesHelper
  # Formatação limitada; HTML enviado pelo usuário permanece escapado.
  def support_message_body(body)
    lines = body.to_s.lines.map do |line|
      escaped = ERB::Util.html_escape(line.chomp)
      formatted = escaped.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>').gsub(/(?<!\*)\*([^*]+)\*(?!\*)/, '<em>\1</em>')
      content = sanitize(formatted.delete_prefix('- '), tags: %w[strong em], attributes: [])
      formatted.start_with?('- ') ? tag.ul(tag.li(content)) : tag.p(content)
    end
    safe_join(lines)
  end
end

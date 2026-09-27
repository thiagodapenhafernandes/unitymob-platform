# Ícones do site público: Bootstrap Icons (já carregado pelo layout em todas as
# páginas e temas). Cada tema só muda cor/tamanho via CSS de .public-theme-icon.
module PublicThemeIconsHelper
  PUBLIC_ICON_FALLBACK = "check2-circle".freeze

  # Nomes que a busca/o conteúdo legados usavam e que o Bootstrap Icons não tem.
  PUBLIC_ICON_ALIASES = {
    "x" => "x-lg",
    "chart" => "graph-up-arrow",
    "alert-triangle" => "exclamation-triangle",
    "message-circle" => "chat-dots",
    "dot" => "dot"
  }.freeze

  # Lista oficial de nomes, lida uma vez do CSS versionado do Bootstrap Icons.
  def self.bootstrap_icon_names
    @bootstrap_icon_names ||= begin
      css = Rails.root.join("app/assets/stylesheets/vendor/bootstrap-icons.css.erb").read
      css.scan(/\.bi-([a-z0-9-]+)::before/).flatten.to_set.freeze
    rescue Errno::ENOENT
      Set.new.freeze
    end
  end

  # `icon` aceita "geo-alt", "bi-geo-alt" ou "bi bi-geo-alt".
  def public_icon(icon, class_name: nil, title: nil, data: {}, aria_hidden: true)
    name = public_icon_name(icon)
    options = {
      class: ["bi", "bi-#{name}", "public-theme-icon", "public-theme-icon--#{name}", class_name].compact_blank.join(" "),
      data: data
    }

    if title.present?
      options[:role] = "img"
      options[:aria] = { label: title }
    elsif aria_hidden
      options[:aria] = { hidden: true }
    end

    tag.i(**options)
  end

  def public_icon_name(icon)
    name = icon.to_s.strip.split(/\s+/).last.to_s.delete_prefix("bi-").gsub(/[^a-z0-9-]/, "")
    name = PUBLIC_ICON_ALIASES.fetch(name, name)
    known = PublicThemeIconsHelper.bootstrap_icon_names
    return name if name.present? && (known.empty? || known.include?(name))

    PUBLIC_ICON_FALLBACK
  end
end

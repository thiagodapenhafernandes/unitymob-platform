module LuxuryThemeHelper
  # Tema luxury ativo nesta requisição (switch do layout público).
  def luxury_theme?
    public_tenant&.public_site_theme_key == "salute_luxury"
  end

  # Entradas do PublicHeaderMenu no formato simples que os componentes luxury consomem.
  # bar_only: true espelha o header padrao (so Entry#bar? na barra do desktop);
  # o restante continua acessivel no drawer mobile.
  def luxury_nav_items(menu_entries, bar_only: false)
    Array(menu_entries).filter_map do |entry|
      next if bar_only && entry.respond_to?(:bar?) && !entry.bar?

      url = entry.url
      label = entry.label.to_s.strip
      next if url.blank? || label.blank?

      {
        label: label, url: url, icon: entry.icon.presence,
        target: (entry.new_tab ? "_blank" : nil), rel: ("noopener" if entry.new_tab)
      }.compact
    end
  end

  # Logo com fallback: variante NAO processada (URL identica a processada;
  # o processamento sai do request para o asset hit). Se falhar, usa o blob
  # original (mesmo comportamento do header padrao), nunca <img> quebrado.
  def luxury_logo(layout_setting)
    logo = layout_setting&.logo
    return unless logo&.attached?
    return logo if logo.content_type == "image/svg+xml"

    logo.variant(resize_to_limit: [400, 120])
  rescue StandardError
    logo
  end
end

module SaluteLuxuryHelper
  # Tema luxury ativo nesta requisição (switch do layout público).
  def salute_luxury_theme?
    public_tenant&.public_site_theme_key == "salute_luxury"
  end

  # Entradas do PublicHeaderMenu no formato simples que os componentes luxury consomem.
  def salute_luxury_nav_items(menu_entries)
    Array(menu_entries).filter_map do |entry|
      url = entry.url
      label = entry.label.to_s.strip
      next if url.blank? || label.blank?

      {
        label: label, url: url, icon: entry.icon.presence,
        target: (entry.new_tab ? "_blank" : nil), rel: ("noopener" if entry.new_tab)
      }.compact
    end
  end
end

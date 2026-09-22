module PublicHeaderHelper
  # Apenas referências visuais; campos vazios continuam herdando o tema público.
  def public_header_color_defaults(tenant:, layout:)
    primary = layout&.primary_color.presence || '#022B3A'
    secondary = layout&.secondary_color.presence || '#053C5E'
    colors = ['#374151', primary, primary, secondary]
    if tenant.public_site_theme_key == 'conexaoimobiliaria'
      colors = ['#FFFFFFDB', '#FFFFFF', '#06121AC7', layout&.accent_color.presence || '#BFAB25']
    elsif tenant.public_site_theme_key == 'default'
      colors = ['#374151', primary, '#022B3A', '#053C5E']
    end
    HomeSetting::HEADER_COLOR_FIELDS.keys.zip(colors).to_h
  end

  def public_menu_link_attrs(entry)
    entry.new_tab ? { target: "_blank", rel: "noopener" } : {}
  end

  def public_menu_label(entry)
    return entry.label unless entry.icon

    safe_join([tag.i(class: "bi bi-#{entry.icon} mr-1"), entry.label], " ")
  end
end

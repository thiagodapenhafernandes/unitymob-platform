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

  # Dados do menu de navegação em tela cheia (public_theme/components/navigation_overlay),
  # iguais em todos os temas: catálogo com contagens, links do menu do admin,
  # contato real da conta e a chamada do header.
  def public_navigation_overlay_data(menu_entries, home_setting:, contact_setting:)
    store = public_tenant.stores.active.order(:id).first
    whatsapp_value = contact_setting.whatsapp_primary.presence || contact_setting.phone.presence
    whatsapp_digits = Phones::Normalizer.call(whatsapp_value)

    {
      catalog_groups: PublicSite::CatalogNavigation.call(tenant: public_tenant).map do |group|
        group.merge(
          url: (habitations_path(group[:filters]) if group[:filters]),
          links: group[:links].map { |link| link.merge(url: habitations_path(link[:filters])) }
        )
      end,
      menu_links: Array(menu_entries).filter_map do |entry|
        next if entry.url.blank? || entry.label.blank?

        { label: entry.label, url: entry.url, icon: entry.icon, active: entry.active, **public_menu_link_attrs(entry) }
      end,
      address: [store&.footer_address_line, store&.footer_city_line].compact_blank.join(" · ").presence,
      phone: (Phones::Normalizer.display(whatsapp_value) if whatsapp_digits.present?),
      phone_url: (contact_setting.whatsapp_primary.present? ? "https://wa.me/#{whatsapp_digits}" : "tel:+#{whatsapp_digits}" if whatsapp_digits.present?),
      cta_label: home_setting&.header_cta_label.presence || PublicHeaderMenu::DEFAULT_CTA_LABEL,
      cta_url: home_setting&.header_cta_url.presence || contato_path,
      media: public_navigation_overlay_media(home_setting)
    }
  end

  private

  # Foto do painel lateral: a escolhida no admin (Identidade → Configurações) ou,
  # sem ela, a primeira do hero da home.
  def public_navigation_overlay_media(home_setting)
    return if home_setting.nil?
    return navigation_overlay_variant(home_setting.navigation_menu_image) if home_setting.navigation_menu_image.attached?

    slide = home_setting.active_hero_slides.with_attached_image.detect { |item| item.image.attached? }
    image = slide&.image || (home_setting.hero_background_desktop if home_setting.hero_background_desktop.attached?)
    return if image.nil?

    navigation_overlay_variant(image)
  rescue StandardError
    nil
  end

  def navigation_overlay_variant(image)
    image.variable? ? image.variant(resize_to_limit: [1200, 1600]) : image
  end
end

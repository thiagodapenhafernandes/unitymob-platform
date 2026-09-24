# Ícones SVG do tema público (port do unitymob-crm, sem dependências).
module PublicThemeIconsHelper
  PUBLIC_THEME_ICON_ALIASES = {
    "bi" => nil,
    "x-lg" => "x",
    "bookmark" => "heart",
    "bookmark-fill" => "heart",
    "bookmark-heart" => "heart",
    "bookmark-heart-fill" => "heart",
    "heart-fill" => "heart",
    "arrows-fullscreen" => "aspect-ratio",
    "building-check" => "building",
    "buildings" => "building",
    "check-all" => "check2",
    "check-circle" => "check2-circle",
    "check-circle-fill" => "check2-circle",
    "shield-fill-check" => "shield-check",
    "share-fill" => "share",
    "box-arrow-up-right" => "share",
    "send-fill" => "send",
    "twitter-x" => "x",
    "link-45deg" => "share",
    "person-circle" => "person",
    "person-standing" => "person",
    "people" => "person",
    "person-badge" => "person",
    "door-closed" => "door-open",
    "house" => "house-heart",
    "house-check" => "house-heart",
    "moisture" => "droplet",
    "graph-up-arrow" => "chart",
    "cash-stack" => "briefcase",
    "mortarboard" => "award",
    "envelope-fill" => "envelope",
    "tag-fill" => "tag",
    "arrow-right-short" => "arrow-right",
    "telephone-outbound" => "telephone",
    "ui-checks-grid" => "grid",
    "check-lg" => "check2",
    "x-circle-fill" => "x-circle",
    "exclamation-triangle-fill" => "alert-triangle",
    "info-circle-fill" => "info-circle",
    "currency-dollar" => "tag",
    "funnel" => "sliders",
    "plus-lg" => "plus",
    "chat-dots" => "message-circle",
    "calendar-check" => "calendar"
  }.freeze

  PUBLIC_THEME_ICON_SHAPES = {
    "alert-triangle" => [[:path, { d: "M12 3l10 18H2L12 3z" }], [:path, { d: "M12 9v5" }], [:path, { d: "M12 17h.01" }]],
    "arrow-down" => [[:path, { d: "M12 5v14" }], [:path, { d: "M6 13l6 6 6-6" }]],
    "arrow-left" => [[:path, { d: "M19 12H5" }], [:path, { d: "M11 6l-6 6 6 6" }]],
    "arrow-right" => [[:path, { d: "M5 12h14" }], [:path, { d: "M13 6l6 6-6 6" }]],
    "aspect-ratio" => [[:rect, { x: 4, y: 5, width: 16, height: 14, rx: 2 }], [:path, { d: "M8 9h3M8 9v3M16 15h-3M16 15v-3" }]],
    "award" => [[:circle, { cx: 12, cy: 8, r: 4 }], [:path, { d: "M9 12l-1 8 4-2 4 2-1-8" }]],
    "briefcase" => [[:rect, { x: 3, y: 7, width: 18, height: 13, rx: 2 }], [:path, { d: "M9 7V5h6v2M3 12h18" }]],
    "building" => [[:path, { d: "M5 21V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16" }], [:path, { d: "M9 8h1M14 8h1M9 12h1M14 12h1M9 16h1M14 16h1M3 21h18" }]],
    "bullseye" => [[:circle, { cx: 12, cy: 12, r: 9 }], [:circle, { cx: 12, cy: 12, r: 5 }], [:circle, { cx: 12, cy: 12, r: 1 }]],
    "calculator" => [[:rect, { x: 5, y: 3, width: 14, height: 18, rx: 2 }], [:path, { d: "M8 7h8M8 11h.01M12 11h.01M16 11h.01M8 15h.01M12 15h.01M16 15h.01M8 19h.01M12 19h.01M16 19h.01" }]],
    "calendar" => [[:rect, { x: 4, y: 5, width: 16, height: 15, rx: 2 }], [:path, { d: "M8 3v4M16 3v4M4 10h16" }]],
    "car-front" => [[:path, { d: "M6 16h12M7 16l1.6-6h6.8L17 16" }], [:circle, { cx: 8, cy: 18, r: 1.5 }], [:circle, { cx: 16, cy: 18, r: 1.5 }], [:path, { d: "M5 16v3M19 16v3" }]],
    "chart" => [[:path, { d: "M4 19h16" }], [:path, { d: "M6 16l4-5 3 3 5-8" }], [:path, { d: "M15 6h3v3" }]],
    "check2" => [[:path, { d: "M5 13l4 4L19 7" }]],
    "check2-circle" => [[:circle, { cx: 12, cy: 12, r: 9 }], [:path, { d: "M8 12l3 3 5-6" }]],
    "chevron-left" => [[:path, { d: "M15 18l-6-6 6-6" }]],
    "chevron-right" => [[:path, { d: "M9 6l6 6-6 6" }]],
    "clock" => [[:circle, { cx: 12, cy: 12, r: 9 }], [:path, { d: "M12 7v6l4 2" }]],
    "door-open" => [[:path, { d: "M5 21h14" }], [:path, { d: "M8 21V5l8-2v18" }], [:path, { d: "M11 12h.01" }]],
    "dot" => [[:circle, { cx: 12, cy: 12, r: 2, fill: "currentColor", stroke: "none" }]],
    "droplet" => [[:path, { d: "M12 3s6 6.2 6 11a6 6 0 0 1-12 0c0-4.8 6-11 6-11z" }]],
    "envelope" => [[:rect, { x: 3, y: 5, width: 18, height: 14, rx: 2 }], [:path, { d: "M4 7l8 6 8-6" }]],
    "eye" => [[:path, { d: "M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6z" }], [:circle, { cx: 12, cy: 12, r: 3 }]],
    "facebook" => [[:path, { d: "M14 8h3V4h-3c-3 0-5 2-5 5v3H6v4h3v5h4v-5h3l1-4h-4V9c0-.6.4-1 1-1z" }]],
    "fire" => [[:path, { d: "M13 3s1 4-2 6c-2 1.5-4 3.7-4 6.5A5 5 0 0 0 12 21a5 5 0 0 0 5-5.5c0-2.8-1.8-4.7-4-6.5 1.5 3-1 4-1 4" }]],
    "gem" => [[:path, { d: "M6 4h12l4 6-10 11L2 10l4-6z" }], [:path, { d: "M2 10h20M8 4l4 17 4-17" }]],
    "geo-alt" => [[:path, { d: "M12 21s7-6.1 7-12a7 7 0 1 0-14 0c0 5.9 7 12 7 12z" }], [:circle, { cx: 12, cy: 9, r: 2.5 }]],
    "grid" => [[:rect, { x: 4, y: 4, width: 6, height: 6, rx: 1 }], [:rect, { x: 14, y: 4, width: 6, height: 6, rx: 1 }], [:rect, { x: 4, y: 14, width: 6, height: 6, rx: 1 }], [:rect, { x: 14, y: 14, width: 6, height: 6, rx: 1 }]],
    "heart" => [[:path, { d: "M20.8 4.6c-1.8-1.8-4.7-1.8-6.5 0L12 6.9 9.7 4.6a4.6 4.6 0 0 0-6.5 6.5L12 20l8.8-8.9a4.6 4.6 0 0 0 0-6.5z" }]],
    "house-heart" => [[:path, { d: "M3 11l9-8 9 8" }], [:path, { d: "M5 10v10h14V10" }], [:path, { d: "M15.5 13.5a2 2 0 0 0-3 0l-.5.5-.5-.5a2 2 0 0 0-3 2.6L12 19l3.5-2.9a2 2 0 0 0 0-2.6z" }]],
    "image" => [[:rect, { x: 4, y: 5, width: 16, height: 14, rx: 2 }], [:circle, { cx: 9, cy: 10, r: 1.5 }], [:path, { d: "M5 17l5-5 3 3 2-2 4 4" }]],
    "images" => [[:rect, { x: 6, y: 7, width: 14, height: 12, rx: 2 }], [:path, { d: "M4 15V5a2 2 0 0 1 2-2h10" }], [:path, { d: "M7 17l4-4 3 3 2-2 3 3" }]],
    "info-circle" => [[:circle, { cx: 12, cy: 12, r: 9 }], [:path, { d: "M12 11v5" }], [:path, { d: "M12 8h.01" }]],
    "instagram" => [[:rect, { x: 4, y: 4, width: 16, height: 16, rx: 5 }], [:circle, { cx: 12, cy: 12, r: 3.5 }], [:circle, { cx: 16.8, cy: 7.2, r: 0.6 }]],
    "linkedin" => [[:rect, { x: 4, y: 4, width: 16, height: 16, rx: 2 }], [:path, { d: "M8 11v5M8 8v.01M12 16v-5M12 13c0-1.4 1-2.2 2.2-2.2S17 11.8 17 14v2" }]],
    "list-ul" => [[:path, { d: "M9 7h11M9 12h11M9 17h11" }], [:path, { d: "M5 7h.01M5 12h.01M5 17h.01" }]],
    "map" => [[:path, { d: "M4 6l5-2 6 2 5-2v14l-5 2-6-2-5 2V6z" }], [:path, { d: "M9 4v14M15 6v14" }]],
    "palette" => [[:path, { d: "M12 3a9 9 0 0 0 0 18h1.5a2 2 0 0 0 1.4-3.4 1.5 1.5 0 0 1 1.1-2.6H18a3 3 0 0 0 3-3c0-5-4-9-9-9z" }], [:path, { d: "M7.5 10h.01M10 7h.01M14 7h.01M16.5 10h.01" }]],
    "person" => [[:circle, { cx: 12, cy: 8, r: 3 }], [:path, { d: "M5 21a7 7 0 0 1 14 0" }]],
    "pencil" => [[:path, { d: "M4 20l4.5-1 10-10a2.1 2.1 0 0 0-3-3l-10 10L4 20z" }], [:path, { d: "M13.5 6.5l4 4" }]],
    "play-circle" => [[:circle, { cx: 12, cy: 12, r: 9 }], [:path, { d: "M10 8l6 4-6 4V8z" }]],
    "plus" => [[:path, { d: "M12 5v14M5 12h14" }]],
    "message-circle" => [[:path, { d: "M21 11.5a8.5 8.5 0 0 1-12.6 7.4L4 20l1.1-4.1A8.5 8.5 0 1 1 21 11.5z" }], [:path, { d: "M8.5 11.5h.01M12 11.5h.01M15.5 11.5h.01" }]],
    "search" => [[:circle, { cx: 11, cy: 11, r: 7 }], [:path, { d: "M16.5 16.5L21 21" }]],
    "send" => [[:path, { d: "M21 3L10 14" }], [:path, { d: "M21 3l-7 18-4-7-7-4 18-7z" }]],
    "share" => [[:path, { d: "M14 4h6v6" }], [:path, { d: "M10 14L20 4" }], [:path, { d: "M20 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h5" }]],
    "shield-check" => [[:path, { d: "M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3z" }], [:path, { d: "M8.5 12l2.5 2.5L16 9" }]],
    "sliders" => [[:path, { d: "M4 7h7M15 7h5M4 17h5M13 17h7" }], [:circle, { cx: 13, cy: 7, r: 2 }], [:circle, { cx: 11, cy: 17, r: 2 }]],
    "stars" => [[:path, { d: "M12 3l1.7 5.2H19l-4.3 3.1 1.7 5.2L12 13.4l-4.4 3.1 1.7-5.2L5 8.2h5.3L12 3z" }]],
    "tag" => [[:path, { d: "M20 13l-7 7L4 11V4h7l9 9z" }], [:circle, { cx: 8.5, cy: 8.5, r: 1 }]],
    "telephone" => [[:path, { d: "M6.5 4.5l2.2-.8 2.2 5-1.5 1.2a13 13 0 0 0 4.7 4.7l1.2-1.5 5 2.2-.8 2.2c-.3.9-1.2 1.5-2.1 1.3C10.5 17.8 6.2 13.5 5.2 6.6c-.2-.9.4-1.8 1.3-2.1z" }]],
    "tiktok" => [[:path, { d: "M14 3v10.5a4.5 4.5 0 1 1-4.5-4.5" }], [:path, { d: "M14 6c1.2 2.4 3 3.7 5 4" }]],
    "trash" => [[:path, { d: "M4 7h16" }], [:path, { d: "M10 11v6M14 11v6" }], [:path, { d: "M6 7l1 14h10l1-14" }], [:path, { d: "M9 7V4h6v3" }]],
    "tv" => [[:rect, { x: 4, y: 6, width: 16, height: 11, rx: 2 }], [:path, { d: "M9 21h6M12 17v4" }]],
    "water" => [[:path, { d: "M3 15c2 0 2-2 4-2s2 2 4 2 2-2 4-2 2 2 4 2 2-2 4-2" }], [:path, { d: "M3 19c2 0 2-2 4-2s2 2 4 2 2-2 4-2 2 2 4 2 2-2 4-2" }]],
    "whatsapp" => [[:path, { d: "M5 20l1.2-3.5A8 8 0 1 1 9 19.1L5 20z" }], [:path, { d: "M9.5 8.7c.2-.5.5-.6.9-.4l1 .5c.3.2.4.5.2.8l-.4.8c.6 1.1 1.4 1.9 2.5 2.5l.8-.4c.3-.2.6-.1.8.2l.5 1c.2.4.1.7-.4.9-.8.4-1.7.4-2.7 0-1.6-.6-3.4-2.4-4-4-.4-1-.4-1.9 0-2.7z" }]],
    "x" => [[:path, { d: "M6 6l12 12M18 6L6 18" }]],
    "x-circle" => [[:circle, { cx: 12, cy: 12, r: 9 }], [:path, { d: "M9 9l6 6M15 9l-6 6" }]],
    "youtube" => [[:path, { d: "M21 8.5a3 3 0 0 0-2.1-2.1C17 6 12 6 12 6s-5 0-6.9.4A3 3 0 0 0 3 8.5 31 31 0 0 0 3 15.5a3 3 0 0 0 2.1 2.1C7 18 12 18 12 18s5 0 6.9-.4A3 3 0 0 0 21 15.5a31 31 0 0 0 0-7z" }], [:path, { d: "M10 9.5v5l5-2.5-5-2.5z" }]]
  }.freeze

  PUBLIC_THEME_LEGACY_RAW_ICON_ALIASES = {
    '<path d="M12 2l8 4v6c0 5-3.5 8-8 10-4.5-2-8-5-8-10V6l8-4z"/>' => "shield-check",
    '<path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/>' => "person",
    '<path d="M3 3v18h18"/><path d="M7 15l4-4 3 3 5-6"/>' => "chart",
    '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="M9 12l2 2 4-4"/>' => "shield-check",
    '<rect x="3" y="4" width="18" height="14" rx="2"/><path d="M3 9h18M8 21h8"/>' => "tv",
    '<path d="M12 8v8M8 12h8"/><circle cx="12" cy="12" r="9"/>' => "check2-circle"
  }.freeze

  def public_svg_icon(icon, class_name: nil, title: nil, data: {}, aria_hidden: true)
    key = public_svg_icon_key(icon)
    shapes = PUBLIC_THEME_ICON_SHAPES.fetch(key, PUBLIC_THEME_ICON_SHAPES.fetch("check2-circle"))
    classes = ["public-theme-icon", "public-theme-icon--#{key}", class_name].compact_blank.join(" ")
    children = shapes.map { |element, attrs| tag.public_send(element, **attrs) }
    html_options = {
      class: classes,
      viewBox: "0 0 24 24",
      width: 24,
      height: 24,
      fill: "none",
      stroke: "currentColor",
      "stroke-width" => 1.8,
      "stroke-linecap" => "round",
      "stroke-linejoin" => "round",
      xmlns: "http://www.w3.org/2000/svg",
      focusable: "false",
      data: data
    }

    if title.present?
      html_options[:role] = "img"
      html_options[:aria] = { label: title }
      children.unshift(tag.title(title))
    elsif aria_hidden
      html_options[:aria] = { hidden: true }
    end

    tag.svg(safe_join(children), **html_options)
  end

  def public_svg_icon_key(icon)
    key = icon.to_s.strip.split(/\s+/).last.to_s.sub(/\Abi-/, "")
    key = key.gsub(/[^a-z0-9-]/, "")
    key = PUBLIC_THEME_ICON_ALIASES.fetch(key, key)
    key = "check2-circle" if key.blank?

    PUBLIC_THEME_ICON_SHAPES.key?(key) ? key : "check2-circle"
  end

  def public_theme_icon(icon)
    raw = icon.to_s.strip
    legacy_alias = PUBLIC_THEME_LEGACY_RAW_ICON_ALIASES[raw]
    return public_svg_icon(legacy_alias) if legacy_alias.present?
    return public_svg_icon(raw) unless raw.start_with?("<")

    tag.svg(
      public_safe_svg(raw),
      class: "public-theme-icon public-theme-icon--custom",
      viewBox: "0 0 24 24",
      width: 24,
      height: 24,
      fill: "none",
      stroke: "currentColor",
      "stroke-width" => 1.8,
      "stroke-linecap" => "round",
      "stroke-linejoin" => "round",
      xmlns: "http://www.w3.org/2000/svg",
      focusable: "false",
      aria: { hidden: true }
    )
  end
end

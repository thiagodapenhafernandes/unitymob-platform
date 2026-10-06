module LandingPagesHelper
  def landing_page_icon_label(label, icon = nil)
    return label if icon.blank? || !icon.to_s.match?(/\A[a-z0-9-]{1,60}\z/)

    safe_join([tag.i(class: "bi bi-#{icon} public-theme-builder-inline-icon", aria: { hidden: true }), label], " ")
  end

  def landing_page_border_style(data, prefix = "block")
    key = prefix.present? ? "#{prefix}_" : ""
    return unless data["#{key}custom_border"] == true
    color = data["#{key}border_color"].to_s
    style = data["#{key}border_style"].to_s
    return unless color.match?(/\A#[0-9a-f]{6}\z/i) && %w[none solid dashed].include?(style)
    "border:#{data["#{key}border_width"].to_i.clamp(0, 12)}px #{style} #{color};border-radius:#{data["#{key}border_radius"].to_i.clamp(0, 64)}px"
  end

  def landing_page_action_color_style(data, prefix = "button")
    key = prefix.present? ? "#{prefix}_" : ""
    styles = []
    if data["#{key}custom_colors"] == true
      background = data["#{key}background_color"].to_s
      text = data["#{key}text_color"].to_s
      styles << "background-color:#{background};border-color:#{background};color:#{text}" if [background, text].all? { |color| color.match?(/\A#[0-9a-f]{6}\z/i) }
    end
    styles << landing_page_creative_style(data, prefix)
    styles << landing_page_border_style(data, prefix)
    styles.compact.presence&.join(";")
  end

  # Never interpolate free-form CSS: colors, enums and numeric limits are checked here too.
  def landing_page_creative_style(data, prefix = "block")
    key = prefix.present? ? "#{prefix}_" : ""
    value = ->(name) { data["#{key}#{name}"] }
    color = ->(name) { candidate = value.call(name).to_s; candidate if candidate.match?(/\A#[0-9a-f]{6}\z/i) }
    alpha = (value.call("background_opacity").nil? ? 100 : value.call("background_opacity").to_i.clamp(0, 100)) / 100.0
    rgba = ->(hex) { "rgba(#{hex.delete_prefix('#').scan(/../).map { |channel| channel.to_i(16) }.join(',')},#{alpha})" }
    styles = []
    gradient = nil
    background = color.call("background_color")
    second = color.call("gradient_color")
    case value.call("background_mode")
    when "transparent" then styles << "background:transparent"
    when "solid" then styles << "background:#{rgba.call(background)}" if background
    when "gradient"
      if background && second
        gradient = value.call("gradient_kind") == "radial" ? "radial-gradient(circle,#{rgba.call(background)},#{rgba.call(second)})" : "linear-gradient(#{value.call('gradient_angle').to_i.clamp(0, 360)}deg,#{rgba.call(background)},#{rgba.call(second)})"
        styles << "background:#{gradient}"
      end
    end
    text_alpha = (value.call("text_opacity").nil? ? 100 : value.call("text_opacity").to_i.clamp(0, 100)) / 100.0
    text_rgba = ->(hex) { "rgba(#{hex.delete_prefix('#').scan(/../).map { |channel| channel.to_i(16) }.join(',')},#{text_alpha})" }
    styles << "color:#{text_rgba.call(color.call('text_color'))}" if text_alpha < 1 && color.call('text_color')
    fonts = { "system" => "system-ui,sans-serif", "arial" => "Arial,sans-serif", "georgia" => "Georgia,serif", "mono" => "ui-monospace,monospace" }
    styles << "font-family:#{fonts[value.call('font_family')]}" if fonts.key?(value.call('font_family'))
    { "font_weight" => %w[300 400 500 600 700 800], "font_style" => %w[normal italic], "text_align" => %w[left center right justify], "text_decoration" => %w[none underline line-through], "text_transform" => %w[none uppercase lowercase capitalize] }.each do |name, allowed|
      styles << "#{name.tr('_', '-')}:#{value.call(name)}" if allowed.include?(value.call(name))
    end
    styles << "font-size:#{value.call('font_size').to_i.clamp(8, 120)}px" if value.call('font_size').to_i.positive?
    styles << "line-height:#{value.call('line_height').to_i.clamp(80, 250) / 100.0}" if value.call('line_height').to_i.positive?
    styles << "letter-spacing:#{value.call('letter_spacing').to_i.clamp(-3, 12)}px" unless value.call('letter_spacing').to_i.zero?
    if value.call('text_gradient') == true && (text = color.call('text_color')) && (text_second = color.call('text_gradient_color'))
      styles << "background-image:linear-gradient(#{value.call('gradient_angle').to_i.clamp(0, 360)}deg,#{text_rgba.call(text)},#{text_rgba.call(text_second)}),#{gradient || 'none'};background-clip:text,border-box;-webkit-background-clip:text,border-box;color:transparent;-webkit-text-fill-color:transparent"
    end
    if value.call('backdrop_enabled') == true
      filter = "blur(#{value.call('backdrop_blur').to_i.clamp(0, 40)}px) saturate(#{value.call('backdrop_saturation').to_i.clamp(0, 200)}%)"
      styles << "backdrop-filter:#{filter};-webkit-backdrop-filter:#{filter}"
    end
    styles.presence&.join(';')
  end

  def landing_page_site_url(page)
    if Tenants::LocalPublicHostOverride.active_host?(request.host)
      public_landing_page_url(page.slug, preview_tenant: page.tenant.slug)
    else
      "#{page.tenant.public_base_url(fallback_base_url: request.base_url)}#{public_landing_page_path(page.slug)}"
    end
  end

  # Existing flat pages keep their layout. A section owns following blocks until the next section.
  def landing_page_groups(blocks)
    groups = [[nil, []]]
    blocks.each do |block|
      if block.block_type == "section"
        groups << [block, []]
      else
        groups.last.last << block
      end
    end
    groups
  end

  def landing_page_block(block, page:, variant:, showcases:, h1: false)
    type = LandingPages::BlockTypes::COLLECTIONS.key?(block.block_type) ? "collection" : block.block_type
    content = render("public_theme/blocks/#{type}", block:, page:, variant:, showcase: showcases[block.object_id], h1:)
    return content if content.to_s.strip.empty?
    tag.div(landing_page_order_elements(content, block), **landing_page_layout_attributes(block))
  end

  # Reorder only sibling elements, retaining their original containers and theme markup.
  def landing_page_order_elements(content, block)
    order = block.value(:element_order).to_s.split(",")
    return content if order.empty?
    fragment = Nokogiri::HTML::DocumentFragment.parse(content)
    nodes = fragment.css("[data-element-field], [data-element-group], .public-theme-block-cover__actions, .public-theme-content-callout__actions, .public-theme-block-collection__items")
    nodes = nodes.reject { |node| node.ancestors.any? { |parent| parent["class"].to_s.split.include?("public-theme-block-layout") } }
    nodes.group_by(&:parent).each_value do |siblings|
      slots = siblings.map do |node|
        key = node['data-element-field'] || node['data-element-group'] || (node['class'].include?('__actions') ? 'actions' : 'items')
        rank = order.index(key) || order.length + siblings.index(node)
        placeholder = Nokogiri::XML::Comment.new(fragment.document, 'element-slot')
        node.add_previous_sibling(placeholder)
        node.unlink
        [placeholder, node, rank]
      end
      sorted = slots.sort_by(&:last)
      slots.each_with_index { |(slot, _, _), index| slot.replace(sorted[index][1]) }
    end
    fragment.to_html.html_safe
  end

  # Escolhe preto ou branco pelo contraste WCAG da cor configurada na conta.
  def landing_page_brand_ink
    color = @layout_setting&.primary_color.presence || "#022B3A"
    return "#ffffff" unless color.match?(/\A#[0-9a-f]{6}\z/i)
    channels = color.delete_prefix("#").scan(/../).map do |channel|
      value = channel.to_i(16) / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
    luminance = channels.zip([0.2126, 0.7152, 0.0722]).sum { |value, weight| value * weight }
    (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05) ? "#000000" : "#ffffff"
  end

  def landing_page_layout_attributes(block)
    values = %i[offset_x offset_y layer layout_min_height mobile_offset_x mobile_offset_y mobile_min_height].to_h { |name| [name, block.value(name).to_i] }
    style = values.map { |name, value| "--lp-#{name.to_s.tr('_', '-')}:#{value}#{'px' unless name == :layer}" }.join(';')
    style += ";--lp-brand-ink:#{landing_page_brand_ink}"
    card_surface = block.block_type == "callout"
    if !card_surface && block.value(:block_custom_colors)
      background = block.value(:block_background_color).to_s
      text = block.value(:block_text_color).to_s
      if [background, text].all? { |color| color.match?(/\A#[0-9a-f]{6}\z/i) }
        style += ";--lp-custom-background:#{background};--lp-custom-text:#{text}"
      end
    end
    style += ";#{landing_page_border_style(block.data)}" if !card_surface && block.value(:block_custom_border)
    creative = landing_page_creative_style(block.data) unless card_surface
    if creative.present?
      # Apply surface properties to the actual section, without adding editor wrappers.
      style += ";" + creative.split(';').map { |property| "--lp-style-#{property}" }.join(';')
    end
    editing = @preview_mode && !@standalone_preview
    { data: (editing ? { block_position: block.position } : nil), id: block.value(:anchor).presence, class: "public-theme-block-layout#{' lp-preview-block' if editing}#{' has-custom-colors' if block.value(:block_custom_colors)}#{' has-creative-style' if creative.present?} lp-content-#{block.value(:content_width) || 'theme'} lp-surface-#{block.value(:surface) || 'inherit'} lp-density-#{block.value(:density) || 'inherit'} lp-type-#{block.value(:typography) || 'inherit'}#{' lp-motion-subtle' if block.value(:motion) == 'subtle'} is-width-#{block.value(:layout_width) || 'theme'} is-height-#{block.value(:layout_height) || 'auto'}#{' has-mobile-layout' if block.value(:mobile_layout)}", style: style }
  end
end

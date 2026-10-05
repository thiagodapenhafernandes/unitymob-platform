module LandingPagesHelper
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
    tag.div(content, **landing_page_layout_attributes(block))
  end

  def landing_page_layout_attributes(block)
    values = %i[offset_x offset_y layer layout_min_height mobile_offset_x mobile_offset_y mobile_min_height].to_h { |name| [name, block.value(name).to_i] }
    style = values.map { |name, value| "--lp-#{name.to_s.tr('_', '-')}:#{value}#{'px' unless name == :layer}" }.join(';')
    { class: "public-theme-block-layout is-width-#{block.value(:layout_width) || 'theme'} is-height-#{block.value(:layout_height) || 'auto'}#{' has-mobile-layout' if block.value(:mobile_layout)}", style: style }
  end
end

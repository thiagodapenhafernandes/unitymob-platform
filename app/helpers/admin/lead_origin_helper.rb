module Admin::LeadOriginHelper
  # Batch context for the origin column. Never use subsequent navigation or the
  # lead's current property as evidence of the original site conversion.
  def lead_origin_site_events(leads, tenant:)
    ids = leads.select { |lead| lead.tenant_id == tenant.id }.map(&:id)
    return {} if ids.empty?

    SeoConversionEvent.joins(:lead).where(leads: { tenant_id: tenant.id }, lead_id: ids, event_type: "lead_created")
      .select("DISTINCT ON (seo_conversion_events.lead_id) seo_conversion_events.*")
      .order(:lead_id, :occurred_at, :id).includes(:habitation).index_by(&:lead_id)
  end

  def lead_origin_campaign_names(leads, tenant:)
    ids = leads.select { |lead| lead.tenant_id == tenant.id && lead.origin.to_s.match?(/whatsapp_campaign/i) }.map(&:id)
    return {} if ids.empty?

    references = LeadActivity.joins(:lead).where(leads: { tenant_id: tenant.id }, lead_id: ids, kind: "whatsapp_campaign_conversion")
      .order(:created_at, :id).pluck(:lead_id, :metadata)
    campaign_ids = references.filter_map { |_, metadata| metadata.to_h["whatsapp_campaign_id"] }
    names = WhatsappCampaign.where(tenant_id: tenant.id, id: campaign_ids).pluck(:id, :name).to_h
    references.each_with_object({}) { |(id, metadata), result| result[id] ||= names[metadata.to_h["whatsapp_campaign_id"].to_i] }
  end

  def lead_origin_column(lead, tenant:, site_event: nil, form_name: nil, campaign_name: nil)
    return unless lead.tenant_id == tenant.id

    info = lead.other_information.to_h
    attribution = lead.attribution_data.to_h
    raw = lead_display_origin(lead, info, attribution).presence || lead.origin.presence || "Origem não informada"
    imported = external_lead_migration_lead?(lead, info, attribution)
    entry = info["whatsapp_entry"].is_a?(Hash) ? info["whatsapp_entry"] : {}
    referral = entry["referral"].is_a?(Hash) ? entry["referral"] : {}
    ctwa = referral["source_type"] == "ad" || raw.match?(/\bctwa\b/i)
    site_event = nil unless site_event&.lead_id == lead.id
    site = site_event.present? || lead.origin.to_s.casecmp("site").zero? ||
      (lead.lead_type.to_s.match?(/\A(?:site|whatsapp_modal|whatsapp_click)\z/i) && lead.source_url.present?)
    brand, label, subtype = lead_origin_identity(raw, ctwa: ctwa)
    if !ctwa && !imported && lead.attribution_channel == "meta_ads"
      brand, label = "meta", "Meta Ads"
    end
    campaign = campaign_name.presence || info["meta_campaign_name"].presence || info["campaign_name"].presence || attribution["campaign_name"].presence || attribution["utm_campaign"].presence
    ad = info["meta_ad_name"].presence || referral["headline"].presence
    context = []
    instagram_entry = info["instagram_entry"].is_a?(Hash) ? info["instagram_entry"] : {}
    if subtype == "Direct"
      context << "Resposta a story" if instagram_entry["story_id"].present?
      instagram_ad = instagram_entry.dig("referral", "ad_id")
      context << "Anúncio ID: #{instagram_ad}" if instagram_ad.is_a?(String) && instagram_ad.match?(/\A[0-9]+\z/)
    end
    context << "Campanha: #{campaign}" if campaign
    context << "Anúncio: #{ad}" if ad
    context << "Anúncio ID: #{referral['source_id']}" if ctwa && ad.blank? && referral["source_id"].present?
    reference = lead_meta_form_reference(lead)
    form = form_name.presence || info["meta_form_name"].presence || info["form_name"].presence || reference["form_id"].presence
    subtype = "Formulários" if brand == "meta" && label == "Meta Ads" && form
    details = [["Origem registrada", raw]]
    details << ["Entrada", "Importação"] if imported
    details << ["Campanha", campaign] if campaign
    details << ["Anúncio", ad] if ad
    details << ["Formulário", form] if form

    if site
      brand = "site"
      label = "Site #{lead_origin_site_name(tenant)}"
      subtype = nil
      page = lead_origin_page(site_event&.source_path.presence || lead.source_url)
      property = site_event&.habitation
      property = nil unless property&.tenant_id == tenant.id
      context = [property ? "Imóvel ##{property.codigo} · #{property.display_title}" : page && "Página: #{page}"].compact
      details << ["Página", page] if page
      details << ["Ação", lead.lead_type] if lead.lead_type.present?
      details << ["Conversão registrada em", l(site_event.occurred_at, format: "%d/%m/%Y %H:%M")] if site_event
    elsif brand == "whatsapp"
      subtype ||= "Campanha" if campaign
      subtype ||= "Importação" if imported
      details << ["Destino", "WhatsApp"] if ctwa
      if context.empty? && imported
        context << "Importação · Origem informada: #{raw}"
      elsif context.empty? && raw.match?(/corretor|atendimento/i)
        context << "Origem informada: #{raw}"
      end
    elsif ctwa
      details << ["Destino", "WhatsApp"]
    elsif form
      context.unshift("Formulário: #{form}")
    elsif brand == "shop"
      place = raw.sub(/\A(?:showroom|vitrine)\s*/i, "").presence
      subtype = place
    end

    {
      label: lead_origin_public_text(label), brand: brand, icon_url: site ? lead_origin_site_icon(tenant) : nil, subtype: lead_origin_public_text(subtype),
      complements: context.map { |text| lead_origin_public_text(text) }.compact_blank.uniq,
      details: details.filter_map { |key, value| [key, lead_origin_public_text(value)] if value.present? }.uniq
    }
  end

  def lead_origin_identity(raw, ctwa: false)
    normalized = raw.to_s.parameterize(separator: "_")
    if normalized.match?(/instagram|\Aig\z/)
      ["instagram", "Instagram", ctwa ? "CTWA" : normalized.include?("direct") ? "Direct" : normalized.include?("leads") ? "Leads" : nil]
    elsif normalized.match?(/facebook|\Afb\z/)
      ctwa ? ["facebook", "Facebook", "CTWA"] : ["meta", normalized.match?(/ads|anuncio/) ? "Meta Ads" : normalized.include?("leads") ? "Facebook Leads" : "Facebook", nil]
    elsif normalized.match?(/\Ameta(?:_ads)?\z/)
      ["meta", normalized == "meta_ads" ? "Meta Ads" : "Meta", nil]
    elsif normalized.include?("whatsapp") || ctwa
      subtype = if ctwa then "CTWA"
      elsif normalized.match?(/organic/) then "Orgânico"
      elsif normalized.match?(/campanha|campaign|disparo/) then "Campanha"
      elsif normalized.match?(/import/) then "Importação"
      end
      ["whatsapp", "WhatsApp", subtype]
    elsif %w[zap_imoveis zapimoveis zap].include?(normalized)
      ["zap", "ZAP Imóveis", nil]
    elsif normalized.match?(/\Aviva_?real(?:_vrsync)?\z/)
      ["vivareal", "VivaReal", nil]
    elsif normalized.match?(/\Aimovel_?web(?:_2)?\z/)
      ["imovelweb", "Imovelweb", nil]
    elsif normalized == "grupo_zap"
      ["buildings", "Grupo Zap", nil]
    elsif normalized.match?(/\Ard_?station(?:_api)?\z/)
      ["rdstation", "RD Station", nil]
    elsif normalized.match?(/showroom|vitrine/)
      ["shop", "Showroom", nil]
    elsif normalized == "cadastro_manual"
      ["person-plus", "Cadastro manual", nil]
    elsif normalized.match?(/\Achaves_na_mao\z/)
      ["chaves", "Chaves na Mão", nil]
    else
      brand = %w[google bing microsoft tiktok linkedin pinterest youtube telegram].find { |key| normalized.start_with?(key) }
      [brand || "tag", raw, nil]
    end
  end

  def lead_origin_site_name(tenant)
    layout = lead_origin_layout(tenant)
    name = (layout&.site_name.presence || tenant.name).to_s.sub(/\Asite\s+/i, "")
    { "salute_imoveis" => "Salute Imóveis", "conexao_imobiliaria" => "Conexão BC" }.fetch(name.parameterize(separator: "_"), name)
  end

  def lead_origin_layout(tenant)
    return @layout_setting if @layout_setting&.tenant_id == tenant.id

    @lead_origin_layouts ||= {}
    return @lead_origin_layouts[tenant.id] if @lead_origin_layouts.key?(tenant.id)

    @lead_origin_layouts[tenant.id] = LayoutSetting.with_attached_favicon.with_attached_logo.find_by(tenant_id: tenant.id)
  end

  def lead_origin_site_icon(tenant)
    layout = lead_origin_layout(tenant)
    return unless layout

    asset = layout.favicon.attached? ? layout.favicon : layout.logo
    rails_storage_proxy_path(asset, only_path: true) if asset.attached?
  end

  def lead_origin_page(value)
    uri = URI.parse(value.to_s)
    return unless uri.scheme.nil? || %w[http https].include?(uri.scheme)

    uri.path.presence # Query and fragments may contain personal data or tokens.
  rescue URI::InvalidURIError
    nil
  end

  def lead_origin_public_text(value)
    return if value.blank?

    value.to_s.gsub(/\bc2s(?:bot)?\b/i, "Importação")
  end
end

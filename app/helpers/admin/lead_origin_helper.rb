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

  # Nomes dos formulários públicos (origin "public_form:slug") por lead.
  def lead_origin_public_form_names(leads, tenant:)
    scoped = leads.select { |lead| lead.tenant_id == tenant.id }
    slugs = scoped.filter_map { |lead| lead.origin.to_s[/\Apublic_form:(.+)\z/i, 1]&.strip }.uniq
    return {} if slugs.empty?

    forms = PublicForm.where(tenant_id: tenant.id, slug: slugs).pluck(:slug, :name, :category)
      .to_h { |slug, name, category| [slug.to_s.downcase, { "name" => name, "category" => category }] }
    scoped.each_with_object({}) do |lead, result|
      slug = lead.origin.to_s[/\Apublic_form:(.+)\z/i, 1]&.strip.to_s.downcase
      result[lead.id] = forms[slug] if slug.present? && forms.key?(slug)
    end
  end

  # Nome do corretor que indicou (share link) por lead.
  def lead_origin_share_names(leads, tenant:)
    scoped = leads.select { |lead| lead.tenant_id == tenant.id && lead.shared_by_admin_user_id.present? }
    return {} if scoped.empty?

    names = AdminUser.where(tenant_id: tenant.id, id: scoped.map(&:shared_by_admin_user_id).uniq).pluck(:id, :name).to_h
    scoped.each_with_object({}) do |lead, result|
      result[lead.id] = names[lead.shared_by_admin_user_id] if names[lead.shared_by_admin_user_id].present?
    end
  end

  # Composição para a ficha (um lead): resolve as consultas da coluna.
  def lead_origin_for(lead, tenant:)
    lead_origin_column(lead, tenant: tenant,
      site_event: lead_origin_site_events([lead], tenant: tenant)[lead.id],
      form_name: lead_table_meta_form_names([lead], tenant: tenant)[lead.id],
      campaign_name: lead_origin_campaign_names([lead], tenant: tenant)[lead.id],
      public_form: lead_origin_public_form_names([lead], tenant: tenant)[lead.id],
      share_name: lead_origin_share_names([lead], tenant: tenant)[lead.id])
  end

  def lead_origin_column(lead, tenant:, site_event: nil, form_name: nil, campaign_name: nil, public_form: nil, share_name: nil)
    return unless lead.tenant_id == tenant.id

    info = lead.other_information.to_h
    attribution = lead.attribution_data.to_h
    raw = lead_display_origin(lead, info, attribution).presence || lead.origin.presence || "Origem não informada"
    imported = external_lead_migration_lead?(lead, info, attribution)
    entry = info["whatsapp_entry"].is_a?(Hash) ? info["whatsapp_entry"] : {}
    referral = entry["referral"].is_a?(Hash) ? entry["referral"] : {}
    ctwa = referral["source_type"] == "ad" || raw.match?(/\bctwa\b/i)
    site_event = nil unless site_event&.lead_id == lead.id
    public_form_lead = lead.origin.to_s.match?(/\Apublic_form:/i)
    share_lead = lead.origin.to_s.match?(/compartilh/i)
    # Indicação entra no `site` para ganhar a linha de conversão (a origem
    # segue Indicação); formulário público é conversão nativa do próprio form.
    site = !public_form_lead && (site_event.present? || lead.origin.to_s.casecmp("site").zero? ||
      (lead.lead_type.to_s.match?(/\A(?:site|whatsapp_modal|whatsapp_click)\z/i) && lead.source_url.present?))
    brand, label, subtype = lead_origin_identity(raw, ctwa: ctwa)
    if !ctwa && !imported && lead.attribution_channel == "meta_ads"
      brand, label = "meta", "Meta Ads"
    elsif !ctwa && !imported && lead.attribution_channel == "tiktok_ads"
      brand, label = "tiktok", "TikTok Ads"
    elsif !ctwa && !imported && lead.attribution_channel == "linkedin_ads"
      brand, label = "linkedin", "LinkedIn Ads"
    end
    # RD/Lovers identificam pelo canal de entrada, não pelo nome — a origem
    # padrão é configurável por conta e pode ter sido renomeada.
    # A Meta é o gerador original do lead e tem integração direta: com
    # evidência Meta (atribuição ou identidade), ela vence o carimbo RD — o
    # RD aparece como contexto de conversão. Sem evidência Meta, o RD segue
    # como rótulo (guardrail).
    rd_entry = !imported && lead_origin_rd_entry?(info)
    lovers_entry = !imported && lead_origin_lovers_entry?(info)
    meta_led = lead.attribution_channel.to_s == "meta_ads" || %w[meta instagram facebook].include?(brand)
    if rd_entry && !meta_led
      brand, label = "rdstation", "RD Station"
    elsif lovers_entry
      brand, label = "lovers", "Lovers"
    end
    portal = lead_origin_portal_name(info)
    if portal && brand == "buildings"
      brand, label = portal
    end
    webhook_lead = !imported && lead.origin.to_s.casecmp("webhook").zero?
    campaign = campaign_name.presence || info["meta_campaign_name"].presence || info["campaign_name"].presence || attribution["campaign_name"].presence || attribution["utm_campaign"].presence
    rd_campaign = info["rd_station_campaign_name"].presence || campaign
    rd_conversion = info["rd_station_conversion_identifier"].presence
    rd_source = info["rd_station_source"].presence
    rd_medium = info["rd_station_medium"].presence
    rd_event_type = info["rd_station_event_type"].presence
    lovers_code = info["lovers_code"].presence
    lovers_status = info["lovers_status"].presence
    lovers_score = info["lovers_score"].presence
    lovers_registration = info["lovers_registration_date"].presence
    lovers_source = info["lovers_source"].presence
    ad = info["meta_ad_name"].presence || referral["headline"].presence
    context = []
    instagram_entry = info["instagram_entry"].is_a?(Hash) ? info["instagram_entry"] : {}
    if subtype == "Direct"
      context << "Resposta a story" if instagram_entry["story_id"].present?
      instagram_ad = hash_dig(instagram_entry, "referral", "ad_id")
      context << "Anúncio ID: #{instagram_ad}" if instagram_ad.is_a?(String) && instagram_ad.match?(/\A[0-9]+\z/)
    end
    context << "Campanha: #{campaign}" if campaign
    context << "Anúncio: #{ad}" if ad
    context << "Anúncio ID: #{referral['source_id']}" if ctwa && ad.blank? && referral["source_id"].present?
    reference = lead_meta_form_reference(lead)
    form = form_name.presence || info["tiktok_form_name"].presence || info["linkedin_form_name"].presence || info["meta_form_name"].presence || info["form_name"].presence || reference["form_id"].presence
    subtype = "Formulários" if brand == "meta" && label == "Meta Ads" && form
    details = [["Origem registrada", raw]]
    details << ["Entrada", "Importação"] if imported
    details << ["Campanha", campaign] if campaign
    details << ["Anúncio", ad] if ad
    details << ["Formulário", form] if form
    if info["linkedin_account_id"].present?
      details << ["Conta de anúncios", info["linkedin_account_id"]]
      details << ["Resposta LinkedIn", info["linkedin_response_id"]]
    end

    # Origem × Conversão: o site só é o rótulo quando é a origem de fato
    # (sem origem externa registrada). Com origem externa, o site entra como
    # linha de conversão aditiva — nunca sobrescreve o rótulo.
    site_pure = site && (raw.blank? || raw.match?(/site|direto|desconhecid|\Adirect\z/i))
    site_page = lead_origin_page(site_event&.source_path.presence || lead.source_url) if site
    site_property = site_event&.habitation if site
    site_property = nil unless site_property&.tenant_id == tenant.id
    site_subtype = if site
      if lead.lead_type.to_s.match?(/whatsapp/i)
        site_property ? "WhatsApp do anúncio" : "WhatsApp do site"
      else
        site_property ? "Formulário do imóvel" : "Contato geral"
      end
    end
    import_source = lead_origin_import_source(lead, info, attribution) if imported
    if site_pure
      brand = "site"
      label = "Site #{lead_origin_site_name(tenant)}"
      subtype = site_subtype
      context = [site_property ? "Imóvel ##{site_property.codigo}" : site_page && "Página: #{site_page}"].compact
      details << ["Página", site_page] if site_page
      details << ["Ação", lead.lead_type] if lead.lead_type.present?
      details << ["Conversão registrada em", l(site_event.occurred_at, format: "%d/%m/%Y %H:%M")] if site_event
    elsif public_form_lead
      form_info = public_form.is_a?(Hash) ? public_form : {}
      slug = lead.origin.to_s[/\Apublic_form:(.+)\z/i, 1]&.strip
      brand = "card-checklist"
      label = "Formulário #{form_info['name'].presence || slug.to_s.tr('_-', ' ').strip.presence || 'do site'}"
      subtype = form_info["category"].presence
      page = lead_origin_page(lead.source_url)
      context = [page && "Página: #{page}"].compact
      details << ["Formulário", form_info["name"].presence || slug] if slug.present? || form_info["name"].present?
      details << ["Página", page] if page
    elsif share_lead
      brand = "share"
      label = "Indicação"
      subtype = share_name.presence || lead.shared_by_admin_user&.name
      context = ["Link do corretor"]
      details << ["Corretor", subtype] if subtype.present?
    elsif brand == "whatsapp"
      subtype ||= "Campanha" if campaign
      subtype ||= "Importação" if imported
      subtype ||= "Conversa"
      details << ["Destino", "WhatsApp"] if ctwa
      # Importação tem linha própria de conversão; aqui só o fallback de origem informada.
      context << "Origem informada: #{raw}" if context.empty? && raw.match?(/corretor|atendimento/i)
    elsif ctwa
      details << ["Destino", "WhatsApp"]
    elsif brand == "rdstation"
      subtype = rd_event_type.to_s.include?("OPPORTUNITY") ? "Oportunidade" : "Conversão"
      context = [
        (rd_campaign && "Campanha: #{rd_campaign}"),
        (rd_conversion && "Conversão: #{rd_conversion}"),
        (rd_source && "Origem original: #{[rd_source, rd_medium].compact.join(' / ')}")
      ].compact
      details << ["Evento RD", rd_event_type]
      details << ["Conversão RD", rd_conversion]
      details << ["Campanha RD", rd_campaign]
      details << ["Origem RD", [rd_source, rd_medium].compact.join(" / ").presence]
    elsif brand == "lovers"
      subtype = "Importação"
      context = [
        (lovers_source && "Origem original: #{lovers_source}"),
        (lovers_status && "Status: #{lovers_status}"),
        (lovers_score && "Score: #{lovers_score}")
      ].compact
      details << ["Código Lovers", lovers_code]
      details << ["Status Lovers", lovers_status]
      details << ["Score Lovers", lovers_score]
      details << ["Cadastro Lovers", lovers_registration]
      details << ["Origem Lovers", lovers_source]
    elsif portal || %w[zap vivareal imovelweb].include?(brand)
      subtype ||= "Portal"
      listing_id = info["origin_listing_id"].presence || info["portal_lead_id"].presence
      context << "Anúncio: #{listing_id}" if listing_id
      details << ["Portal", info["lead_origin"]] if info["lead_origin"].present?
      details << ["Anúncio", listing_id] if listing_id
    elsif imported && import_source.blank?
      brand = "download"
      label = "Importação"
      channel = external_lead_migration_channel_label(lead, info, attribution)
      subtype = channel unless channel == "Integração externa"
      seller = info["external_lead_seller"].is_a?(Hash) ? info["external_lead_seller"] : {}
      context << "Vendedor externo: #{seller['name']}" if seller["name"].present?
      details << ["Vendedor externo", seller["name"]] if seller["name"].present?
    elsif webhook_lead
      brand = "plug"
      label = "Integração"
      subtype = raw unless raw.casecmp("webhook").zero?
      tags = Array(info["webhook_tags"]).map { |tag| tag.to_s.strip }.reject(&:blank?).uniq.first(3)
      context.concat(tags)
      details << ["Recebido por", info["inbound_webhook_user_name"]] if info["inbound_webhook_user_name"].present?
      details << ["Tags", tags.join(", ")] if tags.any?
    elsif form
      context.unshift("Formulário: #{form}")
    elsif brand == "shop"
      place = raw.sub(/\A(?:showroom|vitrine)\s*/i, "").presence
      subtype = place
    end

    # Conversões aditivas: RD, site e importação entram como linhas
    # "Conversão: …" e nunca sobrescrevem o rótulo de origem.
    conversion_context = []
    if rd_entry && brand != "rdstation"
      conversion_context << ["Conversão: RD Station", rd_conversion].compact.join(" · ")
      conversion_context << "Campanha: #{rd_campaign}" if rd_campaign
      details << ["Conversão RD", rd_conversion]
      details << ["Campanha RD", rd_campaign]
      details << ["Origem RD", [rd_source, rd_medium].compact.join(" / ").presence]
    end
    if site && !site_pure
      conversion_context << ["Conversão: Site", site_subtype, site_property && "Imóvel ##{site_property.codigo}"].compact.join(" · ")
      conversion_context << "Página: #{site_page}" if site_property.nil? && site_page
      details << ["Página", site_page] if site_page
      details << ["Ação", lead.lead_type] if lead.lead_type.present?
      details << ["Conversão registrada em", l(site_event.occurred_at, format: "%d/%m/%Y %H:%M")] if site_event
    end
    if imported && import_source.present?
      conversion_context << ["Conversão: Importação", lead_origin_import_channel_label(lead, info, attribution)].compact.join(" · ")
    end

    {
      label: lead_origin_public_text(label), brand: brand, icon_url: site_pure ? lead_origin_site_icon(tenant) : nil, subtype: lead_origin_public_text(subtype),
      complements: (brand == "meta" ? conversion_context : context + conversion_context).map { |text| lead_origin_public_text(text) }.compact_blank.uniq,
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
    elsif normalized.in?(%w[grupo_zap grupo_olx])
      ["buildings", "Grupo OLX", nil]
    elsif normalized.match?(/\Ard_?station(?:_api)?\z/)
      ["rdstation", "RD Station", nil]
    elsif normalized.match?(/\A(?:lead_?)?lovers\z/)
      ["lovers", "Lovers", nil]
    elsif normalized.match?(/showroom|vitrine/)
      ["shop", "Showroom", nil]
    elsif normalized == "cadastro_manual"
      ["person-plus", "Cadastro manual", nil]
    elsif normalized.match?(/\Achaves_na_mao\z/)
      ["chaves", "Chaves na Mão", nil]
    else
      brand = %w[google bing microsoft tiktok linkedin pinterest youtube telegram].find { |key| normalized.start_with?(key) }
      [brand || "tag", Leads::Attribution::SOURCE_LABELS[normalized] || raw, nil]
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

  # Canal detectado pelas chaves gravadas na entrada (não pelo nome da
  # origem, que é configurável): RD grava rd_station_* e Lovers, lovers_*.
  def lead_origin_rd_entry?(info)
    info.keys.any? { |key| key.to_s.start_with?("rd_station_") }
  end

  def lead_origin_lovers_entry?(info)
    info.keys.any? { |key| key.to_s.start_with?("lovers_") }
  end

  # Portal real dentro do payload Grupo OLX (leadOrigin). Retorna o par
  # [brand, label] ou nil quando genérico/ausente (mantém Grupo OLX).
  def lead_origin_portal_name(info)
    name = info["lead_origin"].to_s.parameterize(separator: "_")
    return if name.blank?

    return ["zap", "ZAP Imóveis"] if name.start_with?("zap")
    return ["vivareal", "VivaReal"] if name.include?("viva")
    return ["imovelweb", "Imovelweb"] if name.include?("imovel")
    return ["buildings", "OLX"] if name == "olx"

    nil
  end

  # Fonte específica da importação (lead_source), sem o fallback de canal:
  # quando ausente, a coluna mostra "Importação" com o canal como subtipo,
  # em vez do nome técnico do fornecedor. Com fonte específica, mantém o
  # comportamento atual (ex.: WhatsApp Orgânico importado).
  def lead_origin_import_source(lead, info, attribution)
    candidates = [
      lead.attribution_source,
      hash_dig(attribution, "lead_source", "name"),
      hash_dig(attribution, "lead_source", "alias"),
      hash_dig(info, "external_lead_payload", "attributes", "lead_source", "name"),
      hash_dig(info, "external_lead_payload", "attributes", "lead_source", "alias"),
      hash_dig(info, "attributes", "lead_source", "name"),
      hash_dig(info, "attributes", "lead_source", "alias"),
      hash_dig(info, "c2s_payload", "attributes", "lead_source", "name"),
      hash_dig(info, "c2s_payload", "attributes", "lead_source", "alias")
    ]

    candidates.find { |value| useful_external_origin?(value) }.to_s.squish.presence
  end

  # Canal da importação para a linha de conversão: planilha, migração ou canal declarado.
  def lead_origin_import_channel_label(lead, info, attribution)
    return "Planilha" if lead.attribution_channel.to_s == "Importado da planilha"
    return "Migração" if lead.origin.to_s.match?(/migra/i)

    channel = external_lead_migration_channel_label(lead, info, attribution)
    channel unless channel == "Integração externa"
  end
end

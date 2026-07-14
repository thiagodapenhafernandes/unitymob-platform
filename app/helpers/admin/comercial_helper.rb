module Admin::ComercialHelper
  # --- Timeline unificada ---------------------------------------------------
  # Mapeia um LeadActivity em ícone + cor + texto para o feed cronológico.
  TIMELINE_MAP = {
    "created"            => { icon: "bi-stars",            color: "blue",  label: "Lead criado" },
    "received"           => { icon: "bi-inbox",            color: "gray",  label: "Lead recebido" },
    "assigned_directly"  => { icon: "bi-person-check",     color: "blue",  label: "Atribuído diretamente" },
    "distributed"        => { icon: "bi-diagram-3",        color: "blue",  label: "Distribuído" },
    "dammed"             => { icon: "bi-pause-circle",     color: "amber", label: "Represado" },
    "shark_tank_ready"   => { icon: "bi-lightning",        color: "amber", label: "Liberado para Shark Tank" },
    "pocket_expired"     => { icon: "bi-hourglass-bottom", color: "red",   label: "Tempo de posse expirou" },
    "accepted"           => { icon: "bi-check2-circle",    color: "green", label: "Aceito pelo corretor" },
    "rejected"           => { icon: "bi-x-circle",         color: "red",   label: "Recusado" },
    "status_change"      => { icon: "bi-arrow-left-right", color: "gray",  label: "Etapa alterada" },
    "comment"            => { icon: "bi-chat-left-text",   color: "gray",  label: "Comentário" },
    "note"               => { icon: "bi-pencil-square",    color: "gray",  label: "Contato registrado" },
    "task_created"       => { icon: "bi-check2-square",    color: "amber", label: "Tarefa criada" },
    "task_completed"     => { icon: "bi-check-circle-fill",color: "green", label: "Tarefa concluída" },
    "appointment_created"=> { icon: "bi-calendar-plus",    color: "blue",  label: "Compromisso agendado" },
    "appointment_done"   => { icon: "bi-calendar-check",   color: "green", label: "Compromisso realizado" },
    "proposal_created"   => { icon: "bi-file-earmark-text",color: "gray",  label: "Proposta criada" },
    "proposal_sent"      => { icon: "bi-send",             color: "blue",  label: "Proposta enviada" },
    "proposal_viewed"    => { icon: "bi-eye",              color: "amber", label: "Proposta visualizada" },
    "proposal_aceita"    => { icon: "bi-hand-thumbs-up",   color: "green", label: "Proposta aceita" },
    "proposal_recusada"  => { icon: "bi-hand-thumbs-down", color: "red",   label: "Proposta recusada" },
    "whatsapp_in"        => { icon: "bi-whatsapp",         color: "green", label: "Mensagem recebida" },
    "whatsapp_out"       => { icon: "bi-whatsapp",         color: "blue",  label: "Mensagem enviada" },
    "notification_sent"  => { icon: "bi-send-check",       color: "green", label: "Notificação enviada" },
    "notification_failed"=> { icon: "bi-exclamation-triangle", color: "red", label: "Falha na notificação" },
    "notification_skipped"=> { icon: "bi-slash-circle",    color: "amber", label: "Notificação ignorada" },
    "automation"         => { icon: "bi-lightning-charge", color: "amber", label: "Automação" },
    "automation_event"   => { icon: "bi-lightning-charge", color: "amber", label: "Evento observado" },
    "interest_reprocessed" => { icon: "bi-stars",          color: "blue",  label: "Interesse reprocessado" }
  }.freeze

  def timeline_entry(activity)
    base = TIMELINE_MAP[activity.kind] || { icon: "bi-dot", color: "gray", label: activity.kind.to_s.humanize }
    # "Lead recebido" ganha canal de conversão dinâmico (retroativo: lê o lead).
    if activity.kind.to_s == "received" && activity.lead
      conv = lead_conversion_summary(activity.lead)
      base = base.merge(icon: conv[:icon], color: conv[:color], label: conv[:label])
    end
    detail = timeline_detail(activity)
    base.merge(detail: detail, at: activity.created_at)
  end

  # Resumo de conversão do lead — canal + origem + detalhes, derivado de
  # origin/lead_type/other_information. Fonte única para o cabeçalho e a timeline.
  def lead_conversion_summary(lead)
    info = lead.other_information.is_a?(Hash) ? lead.other_information : {}
    attribution = lead.attribution_data.is_a?(Hash) ? lead.attribution_data : {}
    origin = lead.origin.to_s.downcase
    lead_type = lead.lead_type.to_s.downcase
    attributed_channel = lead.attribution_channel.to_s

    channel, channel_label, icon, color =
      if origin == "webhook" || lead_type == "webhook" || info["inbound_webhook_endpoint"].present?
        [:webhook, "Webhook", "bi-plug", "blue"]
      elsif origin.include?("compartilh") || lead.share_token.present?
        [:share, "Link do corretor", "bi-share", "green"]
      elsif origin.include?("zap") || origin.include?("vivareal") || origin.include?("olx")
        [:portal, "Portal imobiliário", "bi-buildings", "amber"]
      elsif attributed_channel == "google_ads"
        [:google_ads, "Google Ads", "bi-google", "blue"]
      elsif attributed_channel == "meta_ads"
        [:meta, "Meta Ads", "bi-meta", "blue"]
      elsif attributed_channel == "microsoft_ads"
        [:microsoft_ads, "Microsoft Ads", "bi-microsoft", "blue"]
      elsif attributed_channel == "organic_search"
        [:organic_search, lead.origin.presence || "Busca orgânica", "bi-search", "green"]
      elsif attributed_channel == "organic_social"
        [:organic_social, lead.origin.presence || "Social orgânico", "bi-instagram", "green"]
      elsif attributed_channel == "referral"
        [:referral, lead.origin.presence || "Referência", "bi-box-arrow-in-right", "amber"]
      elsif attributed_channel == "direct"
        [:direct, "Direto / origem desconhecida", "bi-compass", "gray"]
      elsif origin.include?("facebook") || origin.include?("instagram") || origin.include?("meta") || info["meta_page_id"].present?
        [:meta, "Meta Ads", "bi-meta", "blue"]
      elsif origin.include?("whatsapp") || lead_type.include?("whatsapp")
        [:whatsapp, "WhatsApp", "bi-whatsapp", "green"]
      elsif lead_type.present? || lead.source_url.present?
        [:site, "Site", "bi-globe2", "blue"]
      else
        [:other, lead.origin.presence || "Origem não informada", "bi-inbox", "gray"]
      end

    source_url   = attribution["landing_url"].presence || lead.source_url.presence || info["source_url"].presence || info["page_url"].presence
    referrer_url = attribution["referrer_url"].presence
    campaign     = attribution["utm_campaign"].presence || info["utm_campaign"].presence || info["campanha"].presence
    received_by  = info["inbound_webhook_user_name"].presence
    webhook_tags = Array(info["webhook_tags"]).compact_blank

    # Campanha de WhatsApp que originou o lead (se veio de resposta a disparo)
    wa_campaign = (lead.whatsapp_campaign_messages.includes(:whatsapp_campaign).first&.whatsapp_campaign&.name rescue nil)

    sentence =
      case channel
      when :google_ads then "Convertido via Google Ads"
      when :meta     then "Convertido via Meta Ads#{" — formulário #{info['meta_form_id']}" if info['meta_form_id'].present?}"
      when :microsoft_ads then "Convertido via Microsoft Ads"
      when :organic_search then "Convertido por busca orgânica"
      when :organic_social then "Convertido por rede social"
      when :referral then "Convertido por site de referência"
      when :direct then "Origem direta ou não identificada"
      when :webhook  then "Convertido via webhook#{" — recebido por #{received_by}" if received_by}"
      when :share    then "Convertido pelo link compartilhado#{" por #{lead.shared_by_admin_user.name}" if lead.shared_by_admin_user}"
      when :portal   then "Convertido via portal (#{channel_label})"
      when :whatsapp then "Convertido respondendo no WhatsApp"
      when :site     then "Convertido no site#{" (#{lead.product})" if lead.product.present?}"
      else "Lead recebido de #{channel_label}"
      end

    # Frase de proveniência (para o bloco no cabeçalho) — literal, "como veio".
    headline =
      case channel
      when :google_ads then "Criado por um anúncio no Google Ads"
      when :meta     then "Criado por um anúncio no Meta Ads (Facebook/Instagram)"
      when :microsoft_ads then "Criado por um anúncio no Microsoft Ads"
      when :organic_search then "Criado por uma busca orgânica (#{channel_label})"
      when :organic_social then "Criado por acesso social (#{channel_label})"
      when :referral then "Criado por uma referência externa (#{channel_label})"
      when :direct then "Acesso direto ou origem não identificada"
      when :webhook  then "Criado via webhook externo#{" · recebido por #{received_by}" if received_by}"
      when :share    then "Criado pelo link compartilhado#{" por #{lead.shared_by_admin_user.name}" if lead.shared_by_admin_user}"
      when :portal   then "Criado por um portal imobiliário (#{channel_label})"
      when :whatsapp then wa_campaign.present? ? "Criado a partir da resposta à campanha de WhatsApp “#{wa_campaign}”" : "Criado a partir de uma conversa no WhatsApp"
      when :site     then "Criado por um formulário do site"
      else "Origem: #{channel_label}"
      end

    {
      channel: channel,
      label: sentence,
      headline: headline,
      channel_label: channel_label,
      icon: icon,
      color: color,
      origin: lead.origin.presence,
      source_url: source_url,
      referrer_url: referrer_url,
      campaign: campaign,
      medium: attribution["utm_medium"].presence,
      term: attribution["utm_term"].presence,
      product: lead.product.presence,
      received_by: received_by,
      tags: webhook_tags
    }
  end

  def timeline_detail(activity)
    meta = activity.metadata.is_a?(Hash) ? activity.metadata : {}
    case activity.kind
    when "note"        then meta["body"].presence
    when "task_created", "task_completed", "appointment_created", "appointment_done" then meta["title"].presence
    when "status_change" then [meta["from"], meta["to"]].compact.join(" → ").presence
    when "distributed", "assigned_directly"
      who = meta["admin_user_name"].presence || activity.lead&.admin_user&.name
      rule = meta["rule_name"].presence
      [("Para #{who}" if who), ("via regra #{rule}" if rule)].compact.join(" · ").presence
    when "automation_event"
      automation_event_detail(activity, meta)
    when "notification_sent", "notification_failed", "notification_skipped"
      notification_activity_detail(meta)
    when "interest_reprocessed" then "#{meta['matches_count'].to_i} imóvel(is) compatível(is), #{meta['confidence'].to_i}% de confiança"
    else nil
    end
  end

  def notification_activity_detail(meta)
    channel = {
      "push" => "Push",
      "whatsapp" => "WhatsApp",
      "email" => "E-mail",
      "webhook" => "Webhook"
    }[meta["channel"].to_s] || meta["channel"].to_s.presence || "Canal"

    status_detail = meta["error"].presence || meta["reason"].presence
    transport = meta["transport"].present? ? "via #{meta['transport']}" : nil
    target = meta["target"].present? ? "para #{meta['target']}" : nil
    [channel, transport, target, status_detail].compact.join(" · ")
  end

  # Detalhe do "Evento observado": para mudança de etapa, mostra a etapa alvo
  # (from→to). Retroativo: se a metadata não tiver, lê o payload do evento.
  def automation_event_detail(activity, meta)
    if meta["event"].to_s == "lead_stage_changed"
      to = meta["to"].presence
      from = meta["from"].presence
      if to.blank? && meta["automation_event_id"].present?
        payload = AutomationEvent.find_by(id: meta["automation_event_id"])&.payload_hash || {}
        to = payload["to"].presence
        from = payload["from"].presence
      end
      return [from, to].compact.join(" → ").presence || meta["label"].presence
    end
    meta["label"].presence
  end

  # --- Barra de funil -------------------------------------------------------
  def funnel_progress(lead, statuses)
    current = Lead.status_value(lead.status)
    idx = statuses.index(current)
    statuses.each_with_index.map do |status, i|
      state = if idx.nil? then (status == current ? :current : :upcoming)
              elsif i < idx then :done
              elsif i == idx then :current
              else :upcoming
              end
      { status: status, state: state }
    end
  end

  # --- SLA (tempo no status atual ~ idade do lead) --------------------------
  def lead_sla(lead)
    hours = ((Time.current - lead.updated_at) / 3600.0)
    if hours < 24 then { color: "green", label: time_ago_in_words(lead.updated_at) + " atrás" }
    elsif hours < 72 then { color: "amber", label: time_ago_in_words(lead.updated_at) + " sem ação" }
    else { color: "red", label: time_ago_in_words(lead.updated_at) + " sem ação" }
    end
  end

  # --- Badges ---------------------------------------------------------------
  def proposal_badge_color(proposal)
    case proposal.status
    when "aceita" then "green"
    when "recusada", "expirada" then "red"
    when "visualizada" then "amber"
    when "enviada" then "blue"
    else "gray"
    end
  end

  def task_badge(task)
    if task.concluida? then { color: "green", label: "Concluída" }
    elsif task.atrasada? then { color: "red", label: "Atrasada" }
    elsif task.due_at.present? then { color: "amber", label: l(task.due_at, format: :short) }
    else { color: "gray", label: "Sem prazo" }
    end
  end

  def push_delivery_event_label(event_type)
    {
      "provider_accepted" => "Gateway aceitou",
      "device_received" => "Device confirmou",
      "provider_failed" => "Falha no provedor",
      "invalid_subscription" => "Subscription inválida",
      "no_active_subscription" => "Sem subscription ativa",
      "push_unavailable" => "Push indisponível"
    }[event_type.to_s] || event_type.to_s.humanize
  end

  def push_delivery_event_tone(event_type)
    {
      "provider_accepted" => "blue",
      "device_received" => "green",
      "provider_failed" => "red",
      "invalid_subscription" => "red",
      "no_active_subscription" => "amber",
      "push_unavailable" => "amber"
    }[event_type.to_s] || "gray"
  end

  def push_delivery_event_device(event)
    agent = event.user_agent.to_s
    return "iPhone / Safari" if agent.include?("iPhone")
    return "Android / Chrome" if agent.include?("Android")
    return "Mac / Safari" if agent.include?("Macintosh") && agent.include?("Safari")
    return "Chrome" if agent.include?("Chrome")

    event.endpoint_host.presence || "Device não identificado"
  end

  def brl(value)
    number_to_currency(value.to_f, unit: "R$ ", separator: ",", delimiter: ".", format: "%u%n")
  end

  def interest_criteria_summary(profile)
    criteria = profile.with_indifferent_access[:criteria].to_h.with_indifferent_access
    items = []
    items << "Cidade: #{criteria[:cities].first(2).join(', ')}" if criteria[:cities].present?
    items << "Bairro: #{criteria[:neighborhoods].first(2).join(', ')}" if criteria[:neighborhoods].present?
    items << "Tipo: #{criteria[:categories].first(2).join(', ')}" if criteria[:categories].present?
    items << "#{criteria[:bedrooms]} dormitório(s)" if criteria[:bedrooms].present?
    if criteria[:min_price_cents].present? || criteria[:max_price_cents].present?
      min = criteria[:min_price_cents].to_i.positive? ? brl(criteria[:min_price_cents].to_i / 100.0) : nil
      max = criteria[:max_price_cents].to_i.positive? ? brl(criteria[:max_price_cents].to_i / 100.0) : nil
      items << "Faixa: #{[min, max].compact.join(' a ')}"
    end
    items.presence || ["Sem critérios suficientes"]
  end

  def interest_event_label(name)
    {
      "page_view" => "Página visitada",
      "property_view" => "Imóvel visualizado",
      "property_whatsapp_click" => "Clique de WhatsApp",
      "property_share" => "Compartilhamento",
      "property_search" => "Busca de imóveis"
    }[name.to_s] || name.to_s.humanize
  end
end

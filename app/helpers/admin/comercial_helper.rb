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
    "automation"         => { icon: "bi-lightning-charge", color: "amber", label: "Automação" },
    "automation_event"   => { icon: "bi-lightning-charge", color: "amber", label: "Evento observado" },
    "interest_reprocessed" => { icon: "bi-stars",          color: "blue",  label: "Interesse reprocessado" }
  }.freeze

  def timeline_entry(activity)
    base = TIMELINE_MAP[activity.kind] || { icon: "bi-dot", color: "gray", label: activity.kind.to_s.humanize }
    detail = timeline_detail(activity)
    base.merge(detail: detail, at: activity.created_at)
  end

  def timeline_detail(activity)
    meta = activity.metadata.is_a?(Hash) ? activity.metadata : {}
    case activity.kind
    when "note"        then meta["body"].presence
    when "task_created", "task_completed", "appointment_created", "appointment_done" then meta["title"].presence
    when "status_change" then [meta["from"], meta["to"]].compact.join(" → ").presence
    when "automation_event" then meta["label"].presence
    when "interest_reprocessed" then "#{meta['matches_count'].to_i} imóvel(is) compatível(is), #{meta['confidence'].to_i}% de confiança"
    else nil
    end
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
